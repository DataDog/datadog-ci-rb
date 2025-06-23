# frozen_string_literal: true

require_relative "base"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # Bitrise: https://bitrise.io/
          # Environment variables docs: https://devcenter.bitrise.io/en/references/available-environment-variables.html
          class Bitrise < Base
            def self.handles?(env)
              env.key?("BITRISE_BUILD_SLUG")
            end

            def provider_name
              Provider::BITRISE
            end

            def pipeline_id
              env["BITRISE_BUILD_SLUG"]
            end

            def pipeline_name
              env["BITRISE_TRIGGERED_WORKFLOW_ID"]
            end

            def pipeline_number
              env["BITRISE_BUILD_NUMBER"]
            end

            def pipeline_url
              env["BITRISE_BUILD_URL"]
            end

            def workspace_path
              env["BITRISE_SOURCE_DIR"]
            end

            def git_repository_url
              env["GIT_REPOSITORY_URL"]
            end

            def git_commit_sha
              env["BITRISE_GIT_COMMIT"] || env["GIT_CLONE_COMMIT_HASH"]
            end

            def git_branch
              env["BITRISEIO_PULL_REQUEST_HEAD_BRANCH"] || env["BITRISE_GIT_BRANCH"]
            end

            def git_tag
              env["BITRISE_GIT_TAG"]
            end

            def git_commit_message
              env["BITRISE_GIT_MESSAGE"]
            end

            def git_commit_author_name
              env["GIT_CLONE_COMMIT_AUTHOR_NAME"]
            end

            def git_commit_author_email
              env["GIT_CLONE_COMMIT_AUTHOR_EMAIL"]
            end

            def git_commit_committer_name
              env["GIT_CLONE_COMMIT_COMMITER_NAME"]
            end

            def git_commit_committer_email
              env["GIT_CLONE_COMMIT_COMMITER_EMAIL"] || env["GIT_CLONE_COMMIT_COMMITER_NAME"]
            end

            def git_pull_request_base_branch
              # from docs: Used only with builds triggered by pull requests: the destination/target branch of the pull request that triggered the build.
              # For example, a pull request wants to merge the content of a branch into the branch main. In this case, this Env Var’s value is main.
              env["BITRISEIO_GIT_BRANCH_DEST"]
            end

            def pr_number
              env["BITRISE_PULL_REQUEST"]
            end
          end
        end
      end
    end
  end
end
