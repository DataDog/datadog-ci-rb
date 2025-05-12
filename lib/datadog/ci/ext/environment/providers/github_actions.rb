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
              "#{github_server_url}/#{env["GITHUB_REPOSITORY"]}/commit/#{env["GITHUB_SHA"]}/checks"
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
              return nil if github_event_json.nil?

              env["GITHUB_BASE_REF"]
            end

            def git_pull_request_base_branch_sha
              return nil if git_pull_request_base_branch.nil?

              event_json = github_event_json
              return nil if event_json.nil?

              event_json.dig("pull_request", "base", "sha")
            rescue => e
              Datadog.logger.error("Failed to extract pull request base branch SHA from GitHub Actions: #{e}")
              Core::Telemetry::Logger.report(e, description: "Failed to extract pull request base branch SHA from GitHub Actions")
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
          end
        end
      end
    end
  end
end
