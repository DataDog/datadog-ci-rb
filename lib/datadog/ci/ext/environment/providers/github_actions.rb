# frozen_string_literal: true

require_relative "../extractor"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # Github Actions: https://github.com/features/actions
          # Environment variables docs: https://docs.github.com/en/actions/learn-github-actions/variables#default-environment-variables
          class GithubActions < Extractor
            private

            # overridden methods
            def provider_name
              "github"
            end

            def job_name
              env["GITHUB_JOB"]
            end

            def job_url
              "#{env["GITHUB_SERVER_URL"]}/#{env["GITHUB_REPOSITORY"]}/commit/#{env["GITHUB_SHA"]}/checks"
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
              res = "#{env["GITHUB_SERVER_URL"]}/#{env["GITHUB_REPOSITORY"]}/actions/runs/#{env["GITHUB_RUN_ID"]}"
              res = "#{res}/attempts/#{env["GITHUB_RUN_ATTEMPT"]}" if env["GITHUB_RUN_ATTEMPT"]
              res
            end

            def workspace_path
              env["GITHUB_WORKSPACE"]
            end

            def git_repository_url
              "#{env["GITHUB_SERVER_URL"]}/#{env["GITHUB_REPOSITORY"]}.git"
            end

            def git_commit_sha
              env["GITHUB_SHA"]
            end

            def git_branch
              return @branch if defined?(@branch)

              set_branch_and_tag
              @branch
            end

            def git_tag
              return @tag if defined?(@tag)

              set_branch_and_tag
              @tag
            end

            def ci_env_vars
              {
                "GITHUB_SERVER_URL" => env["GITHUB_SERVER_URL"],
                "GITHUB_REPOSITORY" => env["GITHUB_REPOSITORY"],
                "GITHUB_RUN_ID" => env["GITHUB_RUN_ID"],
                "GITHUB_RUN_ATTEMPT" => env["GITHUB_RUN_ATTEMPT"]
              }.reject { |_, v| v.nil? }.to_json
            end

            # github-specific methods

            def ref
              return @ref if defined?(@ref)

              @ref = env["GITHUB_HEAD_REF"]
              @ref = env["GITHUB_REF"] if @ref.nil? || @ref.empty?
              @ref
            end

            def set_branch_and_tag
              @branch, @tag = branch_or_tag(ref)
            end
          end
        end
      end
    end
  end
end