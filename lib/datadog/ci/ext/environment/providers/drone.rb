# frozen_string_literal: true

require "json"

require_relative "base"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # Drone CI: https://drone.io/
          # Environment variables docs: https://docs.drone.io/pipeline/environment/reference/
          class Drone < Base
            def self.handles?(env)
              env.key?("DRONE")
            end

            def provider_name
              Provider::DRONE
            end

            def job_name
              env["DRONE_STEP_NAME"]
            end

            def pipeline_number
              env["DRONE_BUILD_NUMBER"]
            end

            def pipeline_url
              env["DRONE_BUILD_LINK"]
            end

            def stage_name
              env["DRONE_STAGE_NAME"]
            end

            def workspace_path
              env["DRONE_WORKSPACE"]
            end

            def git_repository_url
              env["DRONE_GIT_HTTP_URL"]
            end

            def git_commit_sha
              env["DRONE_COMMIT_SHA"]
            end

            def git_branch
              env["DRONE_BRANCH"]
            end

            def git_tag
              env["DRONE_TAG"]
            end

            def git_commit_author_name
              env["DRONE_COMMIT_AUTHOR_NAME"]
            end

            def git_commit_author_email
              env["DRONE_COMMIT_AUTHOR_EMAIL"]
            end

            def git_commit_message
              env["DRONE_COMMIT_MESSAGE"]
            end

            def git_pull_request_base_branch
              env["DRONE_TARGET_BRANCH"]
            end

            def pr_number
              env["DRONE_PULL_REQUEST"]
            end
          end
        end
      end
    end
  end
end
