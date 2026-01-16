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
            # Default path to GitHub Actions runner diagnostics folder
            GITHUB_RUNNER_DIAG_PATH = "/home/runner/actions-runner/_diag"

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
              return nil unless Dir.exist?(GITHUB_RUNNER_DIAG_PATH)

              worker_files = Dir.glob(File.join(GITHUB_RUNNER_DIAG_PATH, "Worker_*.log")).sort
              return nil if worker_files.empty?

              # Use the most recent worker file (last in sorted order)
              worker_file = worker_files.last
              extract_check_run_id_from_worker_file(worker_file)
            rescue => e
              Datadog.logger.debug("Failed to extract numeric job ID from GitHub Actions runner diagnostics: #{e}")
              nil
            end

            def extract_check_run_id_from_worker_file(file_path)
              return nil unless File.exist?(file_path)

              # On self-hosted runners, Worker_*.log files can be appended across multiple jobs.
              # We scan the entire file and return the last check_run_id found to get the current job's ID.
              last_check_run_id = nil

              File.foreach(file_path) do |line|
                # Each line in the Worker log file can contain JSON data
                # We're looking for the "job" object with "check_run_id" in its "d" array
                next unless line.include?('"check_run_id"')

                check_run_id = parse_check_run_id_from_line(line)
                last_check_run_id = check_run_id if check_run_id
              end

              last_check_run_id
            rescue => e
              Datadog.logger.debug("Failed to parse Worker log file #{file_path}: #{e}")
              nil
            end

            def parse_check_run_id_from_line(line)
              # Find JSON object in the line - it may be prefixed with timestamp
              json_start = line.index("{")
              return nil unless json_start

              json_str = line[json_start..] || ""
              json_data = JSON.parse(json_str)

              # Navigate to job.d array and find check_run_id
              job_data = json_data.dig("job", "d")
              return nil unless job_data.is_a?(Array)

              job_data.each do |item|
                next unless item.is_a?(Hash)
                next unless item["k"] == "check_run_id"

                value = item["v"]
                # The value might be a float (55411116365.0), convert to integer string
                return value.to_i.to_s if value
              end

              nil
            rescue JSON::ParserError
              nil
            end
          end
        end
      end
    end
  end
end
