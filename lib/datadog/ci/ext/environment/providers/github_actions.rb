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

            def additional_tags
              base_ref = env["GITHUB_BASE_REF"]
              return {} if base_ref.nil? || base_ref.empty?

              # @type var result: Hash[String, String]
              result = {
                Git::TAG_PULL_REQUEST_BASE_BRANCH => base_ref
              }

              event_path = env["GITHUB_EVENT_PATH"]
              event_json = JSON.parse(File.read(event_path))

              head_sha = event_json.dig("pull_request", "head", "sha")
              result[Git::TAG_COMMIT_HEAD_SHA] = head_sha if head_sha

              base_sha = event_json.dig("pull_request", "base", "sha")
              result[Git::TAG_PULL_REQUEST_BASE_BRANCH_SHA] = base_sha if base_sha

              result
            rescue => e
              Datadog.logger.error("Failed to extract additional tags from GitHub Actions: #{e}")
              Core::Telemetry::Logger.report(e, description: "Failed to extract additional tags from GitHub Actions")

              {}
            end

            private

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
