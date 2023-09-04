# frozen_string_literal: true

require_relative "../extractor"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # Jenkins: https://www.jenkins.io/
          # Environment variables docs: https://www.jenkins.io/doc/book/pipeline/jenkinsfile/#using-environment-variables
          class Jenkins < Extractor
            private

            # overridden methods
            def provider_name
              "jenkins"
            end

            def pipeline_id
              env["BUILD_TAG"]
            end

            def pipeline_name
              if (name = env["JOB_NAME"])
                name = name.gsub("/#{normalize_ref(git_branch)}", "") if git_branch
                name = name.split("/").reject { |v| v.nil? || v.include?("=") }.join("/")
              end
              name
            end

            def pipeline_number
              env["BUILD_NUMBER"]
            end

            def pipeline_url
              env["BUILD_URL"]
            end

            def workspace_path
              env["WORKSPACE"]
            end

            def node_name
              env["NODE_NAME"]
            end

            def node_labels
              env["NODE_LABELS"] && env["NODE_LABELS"].split.to_json
            end

            def git_repository_url
              env["GIT_URL"] || env["GIT_URL_1"]
            end

            def git_commit_sha
              env["GIT_COMMIT"]
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
                "DD_CUSTOM_TRACE_ID" => env["DD_CUSTOM_TRACE_ID"]
              }.to_json
            end

            # jenkins-specific methods

            def set_branch_and_tag
              @branch, @tag = branch_or_tag(env["GIT_BRANCH"])
            end
          end
        end
      end
    end
  end
end
