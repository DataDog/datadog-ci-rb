# frozen_string_literal: true

require "json"

require_relative "base"
require_relative "../../../utils/url"

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
              "github"
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

            private

            def github_server_url
              return @github_server_url if defined?(@github_server_url)

              @github_server_url ||= Utils::Url.filter_sensitive_info(env["GITHUB_SERVER_URL"])
            end
          end
        end
      end
    end
  end
end
