# frozen_string_literal: true

require "tmpdir"
require "fileutils"

require_relative "local_repository"
require_relative "search_commits"
require_relative "upload_packfile"
require_relative "packfiles"

module Datadog
  module CI
    module Git
      class TreeUploader
        attr_reader :api

        def initialize(api:)
          @api = api
        end

        def call(repository_url)
          if api.nil?
            Datadog.logger.debug("API is not configured, aborting git upload")
            return
          end

          Datadog.logger.debug { "Uploading git tree for repository #{repository_url}" }

          latest_commits = LocalRepository.git_commits
          head_commit = latest_commits&.first
          if head_commit.nil?
            Datadog.logger.debug("Got empty latest commits list, aborting git upload")
            return
          end

          begin
            # This "far from perfect" code stays here as is and not split up multiple methods and classes because
            # the unshallowing logic with optimizations is inherently complex and I don't hide this
            # complexity on purpose.
            excluded_commits, included_commits = split_known_commits(repository_url, latest_commits)
            if included_commits.empty?
              if LocalRepository.git_shallow_clone?
                Datadog.logger.debug("Detected shallow clone, unshallowing the git repository")

                unshallow_result = LocalRepository.git_unshallow
                if unshallow_result.nil?
                  Datadog.logger.debug("Failed to unshallow the git repository, aborting git upload")
                  return
                end

                excluded_commits, included_commits = split_known_commits(
                  repository_url,
                  LocalRepository.git_commits
                )

                if included_commits.empty?
                  Datadog.logger.debug("No new commits to upload after unshallowing")
                  return
                end
              else
                Datadog.logger.debug("No new commits to upload")
                return
              end
            end
          rescue SearchCommits::ApiError => e
            Datadog.logger.debug("SearchCommits failed with #{e}, aborting git upload")
            return
          end

          Datadog.logger.debug { "Uploading packfiles for commits: #{included_commits}" }
          uploader = UploadPackfile.new(
            api: api,
            head_commit_sha: head_commit,
            repository_url: repository_url
          )
          Packfiles.generate(included_commits: included_commits, excluded_commits: excluded_commits) do |filepath|
            uploader.call(filepath: filepath)
          rescue UploadPackfile::ApiError => e
            Datadog.logger.debug("Packfile upload failed with #{e}")
            break
          end
        end

        private

        def split_known_commits(repository_url, latest_commits)
          Datadog.logger.debug { "Checking the latest commits list with backend: #{latest_commits}" }
          backend_commits = SearchCommits.new(api: api).call(repository_url, latest_commits)
          latest_commits.partition do |commit|
            backend_commits.include?(commit)
          end
        end
      end
    end
  end
end
