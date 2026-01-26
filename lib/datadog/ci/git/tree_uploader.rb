# frozen_string_literal: true

require "tmpdir"
require "fileutils"

require_relative "local_repository"
require_relative "search_commits"
require_relative "upload_packfile"
require_relative "packfiles"

require_relative "../ext/telemetry"
require_relative "../utils/telemetry"
require_relative "../utils/test_run"

module Datadog
  module CI
    module Git
      class TreeUploader
        attr_reader :api, :force_unshallow

        def initialize(api:, force_unshallow: false)
          @api = api
          @force_unshallow = force_unshallow
        end

        def call(repository_url)
          if api.nil?
            Datadog.logger.debug("API is not configured, aborting git upload")
            return
          end

          if test_tracing_component.client_process?
            Datadog.logger.debug("Test tracing component is running in client process, aborting git upload")
            return
          end

          if Utils::TestRun.test_optimization_data_cached?
            Datadog.logger.debug("DDTest cache found, git upload already done by DDTest tool, skipping git upload")
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

            # We optimize unshallowing process by checking the latest available commits with backend:
            # if they are already known to backend, then we don't have to unshallow.
            #
            # Sometimes we need to unshallow anyway: for impacted tests detection feature for example we need
            # to calculate git diffs locally. In this case we skip the optimization and always unshallow.
            if new_commits.empty? && !@force_unshallow
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
          packfiles_count = 0
          Packfiles.generate(included_commits: new_commits, excluded_commits: known_commits) do |filepath|
            packfiles_count += 1
            uploader.call(filepath: filepath)
          rescue UploadPackfile::ApiError => e
            Datadog.logger.debug("Packfile upload failed with #{e}")
            break
          end

          Utils::Telemetry.distribution(Ext::Telemetry::METRIC_GIT_REQUESTS_OBJECT_PACK_FILES, packfiles_count.to_f)
        ensure
          Datadog.logger.debug("Git tree upload finished")
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

        def test_tracing_component
          Datadog.send(:components).test_tracing
        end
      end
    end
  end
end
