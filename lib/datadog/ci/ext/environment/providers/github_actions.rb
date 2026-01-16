# frozen_string_literal: true

require "json"

require "datadog/core/telemetry/logging"
require "datadog/core/utils/url"

require_relative "base"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # Github Actions: https://github.com/features/actions
          # Environment variables docs: https://docs.github.com/en/actions/learn-github-actions/variables#default-environment-variables
          class GithubActions < Base
            # Paths to GitHub Actions runner diagnostics folder
            # GitHub-hosted (SaaS) runners use the cached path, self-hosted runners use the non-cached path
            GITHUB_RUNNER_DIAG_PATHS = [
              "/home/runner/actions-runner/cached/_diag", # GitHub-hosted (SaaS) runners
              "/home/runner/actions-runner/_diag"         # Self-hosted runners
            ].freeze

            def self.handles?(env)
              env.key?("GITHUB_SHA")
            end

            def provider_name
              Provider::GITHUB
            end

            def job_name
              env["GITHUB_JOB"]
            end

            def job_url
              numeric_id = numeric_job_id
              if numeric_id
                "#{github_server_url}/#{env["GITHUB_REPOSITORY"]}/actions/runs/#{env["GITHUB_RUN_ID"]}/job/#{numeric_id}"
              else
                "#{github_server_url}/#{env["GITHUB_REPOSITORY"]}/commit/#{env["GITHUB_SHA"]}/checks"
              end
            end

            def job_id
              numeric_job_id || env["GITHUB_JOB"]
            end

            def pipeline_id
              env["GITHUB_RUN_ID"]
            end

            def pipeline_name
              env["GITHUB_WORKFLOW"]
            end

            def pipeline_number
              env["GITHUB_RUN_NUMBER"]
            end

            def pipeline_url
              res = "#{github_server_url}/#{env["GITHUB_REPOSITORY"]}/actions/runs/#{env["GITHUB_RUN_ID"]}"
              res = "#{res}/attempts/#{env["GITHUB_RUN_ATTEMPT"]}" if env["GITHUB_RUN_ATTEMPT"]
              res
            end

            def workspace_path
              env["GITHUB_WORKSPACE"]
            end

            def git_repository_url
              "#{github_server_url}/#{env["GITHUB_REPOSITORY"]}.git"
            end

            def git_commit_sha
              env["GITHUB_SHA"]
            end

            def git_branch_or_tag
              ref = env["GITHUB_HEAD_REF"]
              ref = env["GITHUB_REF"] if ref.nil? || ref.empty?
              ref
            end

            def ci_env_vars
              {
                "GITHUB_SERVER_URL" => github_server_url,
                "GITHUB_REPOSITORY" => env["GITHUB_REPOSITORY"],
                "GITHUB_RUN_ID" => env["GITHUB_RUN_ID"],
                "GITHUB_RUN_ATTEMPT" => env["GITHUB_RUN_ATTEMPT"]
              }.reject { |_, v| v.nil? }.to_json
            end

            def git_pull_request_base_branch
              env["GITHUB_BASE_REF"]
            end

            def git_pull_request_base_branch_head_sha
              return nil if git_pull_request_base_branch.nil?

              event_json = github_event_json
              return nil if event_json.nil?

              event_json.dig("pull_request", "base", "sha")
            rescue => e
              Datadog.logger.error("Failed to extract pull request base branch head SHA from GitHub Actions: #{e}")
              Core::Telemetry::Logger.report(e, description: "Failed to extract pull request base branch head SHA from GitHub Actions")
              nil
            end

            def git_commit_head_sha
              return nil if git_pull_request_base_branch.nil?

              event_json = github_event_json
              return nil if event_json.nil?

              event_json.dig("pull_request", "head", "sha")
            rescue => e
              Datadog.logger.error("Failed to extract commit head SHA from GitHub Actions: #{e}")
              Core::Telemetry::Logger.report(e, description: "Failed to extract commit head SHA from GitHub Actions")
              nil
            end

            def pr_number
              event_json = github_event_json
              return nil if event_json.nil?

              event_json["number"]
            rescue => e
              Datadog.logger.error("Failed to extract PR number from GitHub Actions: #{e}")
              Core::Telemetry::Logger.report(e, description: "Failed to extract PR number from GitHub Actions")
              nil
            end

            private

            def github_event_json
              return @github_event_json if defined?(@github_event_json)

              event_path = env["GITHUB_EVENT_PATH"]
              return @github_event_json = nil if event_path.nil? || event_path.empty?

              @github_event_json = JSON.parse(File.read(event_path))
            rescue => e
              Datadog.logger.error("Failed to parse GitHub event JSON: #{e}")
              Core::Telemetry::Logger.report(e, description: "Failed to parse GitHub event JSON")
              @github_event_json = nil
            end

            def github_server_url
              return @github_server_url if defined?(@github_server_url)

              @github_server_url ||= Datadog::Core::Utils::Url.filter_basic_auth(env["GITHUB_SERVER_URL"])
            end

            # Returns numeric job ID from environment variable or runner diagnostics.
            # Priority:
            # 1. JOB_CHECK_RUN_ID environment variable (GitHub Actions feature pending)
            # 2. Worker_*.log files in the runner's _diag folder (fallback)
            def numeric_job_id
              return @numeric_job_id if defined?(@numeric_job_id)

              @numeric_job_id = env["JOB_CHECK_RUN_ID"] || extract_numeric_job_id_from_diag_files
            end

            def extract_numeric_job_id_from_diag_files
              GITHUB_RUNNER_DIAG_PATHS.each do |diag_path|
                next unless Dir.exist?(diag_path)

                worker_files = Dir.glob(File.join(diag_path, "Worker_*.log")).sort
                next if worker_files.empty?

                # Use the most recent worker file (last in sorted order)
                worker_file = worker_files.last
                check_run_id = extract_check_run_id_from_worker_file(worker_file)
                return check_run_id if check_run_id
              end

              nil
            rescue => e
              Datadog.logger.debug("Failed to extract numeric job ID from GitHub Actions runner diagnostics: #{e}")
              nil
            end

            # Regex to extract check_run_id value from Worker log files.
            # The log format varies between GitHub-hosted and self-hosted runners,
            # so we use regex instead of JSON parsing for robustness.
            # Matches patterns like: "k": "check_run_id" ... "v": 12345 or "v": 12345.0
            CHECK_RUN_ID_REGEX = /"k":\s*"check_run_id"[^}]*"v":\s*(\d+)(?:\.\d+)?/

            def extract_check_run_id_from_worker_file(file_path)
              return nil unless File.exist?(file_path)

              content = File.read(file_path)

              # Find all check_run_id values in the file.
              # On self-hosted runners, Worker_*.log files can be appended across multiple jobs,
              # so we use the last match to get the current job's ID.
              # flatten because scan with capture groups returns Array[Array[String]]
              matches = content.scan(CHECK_RUN_ID_REGEX).flatten
              matches.last
            rescue => e
              Datadog.logger.debug("Failed to parse Worker log file #{file_path}: #{e}")
              nil
            end
          end
        end
      end
    end
  end
end
