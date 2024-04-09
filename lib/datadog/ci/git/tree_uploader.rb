# frozen_string_literal: true

require "tmpdir"
require "fileutils"

require_relative "local_repository"
require_relative "search_commits"
require_relative "upload_packfile"

module Datadog
  module CI
    module Git
      class TreeUploader
        attr_reader :api

        def initialize(api:)
          @api = api
        end

        # 1. Get repository URL
        def call(repository_url)
          # 2. Check if the repository clone is shallow and unshallow if appropriate
          # TO BE ADDED IN CIVIS-2863
          # 3. Get a maximum of 1000 latest commits in the last month with git log
          latest_commits = LocalRepository.git_commits
          head_commit = latest_commits.first
          if head_commit.nil?
            Datadog.logger.debug("Got empty latest commits list, aborting git upload")
            return
          end

          # 4. Search which commits are present on backend
          backend_commits = nil
          begin
            backend_commits = SearchCommits.new(api: api).call(repository_url, latest_commits)
          rescue SearchCommits::ApiError => e
            Datadog.logger.debug("SearchCommits failed with #{e}, aborting git upload")
            return
          end

          # 5. Get commits and trees excluding the backend commits
          # 6. Generate pack files
          included_commits = latest_commits.filter do |commit|
            !backend_commits.include?(commit)
          end

          if included_commits.empty?
            Datadog.logger.debug("No new commits to upload")
            return
          end

          uploader = UploadPackfile.new(
            api: api,
            head_commit_sha: head_commit,
            repository_url: repository_url
          )

          # TODO: extract packfile generation to a separate class that yields files one by one
          # hopefully it'll make it easier to test
          Dir.mktmpdir do |tmpdir|
            packfiles_folder = tmpdir
            prefix = LocalRepository.git_generate_packfiles(
              included_commits: included_commits,
              excluded_commits: backend_commits.to_a,
              path: packfiles_folder
            )

            if prefix.nil?
              Datadog.logger.debug("packfiles generation failed, retrying with different folder")

              packfiles_folder = File.join(Dir.pwd, "tmp", "packfiles")
              FileUtils.mkdir_p(packfiles_folder)

              prefix = LocalRepository.git_generate_packfiles(
                included_commits: included_commits,
                excluded_commits: backend_commits.to_a,
                path: packfiles_folder
              )

              if prefix.nil?
                Datadog.logger.debug("packfiles generation failed, aborting git upload")
                break
              end
            end

            packfiles = Dir.entries(packfiles_folder) - %w[. ..]
            if packfiles.empty?
              Datadog.logger.debug("Empty packfiles list, nothing to upload")
              break
            end

            # 7. Upload packfiles via an HTTP multipart POST to /api/v2/git/repository/packfile for each generated packfile
            packfiles.each do |packfile|
              filename = File.basename(packfile)

              next unless filename.start_with?(prefix)
              next unless filename.end_with?(".pack")

              uploader.call(filepath: packfile)
            rescue UploadPackfile::ApiError => e
              Datadog.logger.debug("Packfile upload failed with #{e}")
              break
            end
          end
        end
      end
    end
  end
end
