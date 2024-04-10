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
            # ask the backend for the list of commits it already has
            known_commits, new_commits = fetch_known_commits_and_split(repository_url, latest_commits)
            # if all commits are present in the backend, we don't need to upload anything
            if new_commits.empty?
              Datadog.logger.debug("No new commits to upload")
              return
            end

            # quite often we deal with shallow clones in CI environment
            if LocalRepository.git_shallow_clone? && LocalRepository.git_unshallow
              Datadog.logger.debug("Detected shallow clone and unshallowed the repository, repeating commits search")

              # re-run the search with the updated commit list after unshallowing
              known_commits, new_commits = fetch_known_commits_and_split(
                repository_url,
                LocalRepository.git_commits
              )
            end
          rescue SearchCommits::ApiError => e
            Datadog.logger.debug("SearchCommits failed with #{e}, aborting git upload")
            return
          end

          Datadog.logger.debug { "Uploading packfiles for commits: #{new_commits}" }
          uploader = UploadPackfile.new(
            api: api,
            head_commit_sha: head_commit,
            repository_url: repository_url
          )
          Packfiles.generate(included_commits: new_commits, excluded_commits: known_commits) do |filepath|
            uploader.call(filepath: filepath)
          rescue UploadPackfile::ApiError => e
            Datadog.logger.debug("Packfile upload failed with #{e}")
            break
          end
        end

        private

        # Split the latest commits list into known and new commits
        # based on the backend response provided by /search_commits endpoint
        def fetch_known_commits_and_split(repository_url, latest_commits)
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
