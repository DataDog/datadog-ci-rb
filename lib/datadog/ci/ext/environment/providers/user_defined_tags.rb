# frozen_string_literal: true

require_relative "base"
require_relative "../../git"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # Parses user defined git data from the environment variables
          # User documentation: https://docs.datadoghq.com/continuous_integration/troubleshooting/#data-appears-in-test-runs-but-not-tests
          class UserDefinedTags < Base
            def git_repository_url
              git_config = datadog_git_configuration
              if git_config&.respond_to?(:repository_url)
                git_config.repository_url
              else
                env[Git::ENV_REPOSITORY_URL]
              end
            end

            def git_commit_sha
              git_config = datadog_git_configuration
              if git_config&.respond_to?(:commit_sha)
                git_config.commit_sha
              else
                env[Git::ENV_COMMIT_SHA]
              end
            end

            def git_branch
              env[Git::ENV_BRANCH]
            end

            def git_tag
              env[Git::ENV_TAG]
            end

            def git_commit_message
              env[Git::ENV_COMMIT_MESSAGE]
            end

            def git_commit_author_name
              env[Git::ENV_COMMIT_AUTHOR_NAME]
            end

            def git_commit_author_email
              env[Git::ENV_COMMIT_AUTHOR_EMAIL]
            end

            def git_commit_author_date
              env[Git::ENV_COMMIT_AUTHOR_DATE]
            end

            def git_commit_committer_name
              env[Git::ENV_COMMIT_COMMITTER_NAME]
            end

            def git_commit_committer_email
              env[Git::ENV_COMMIT_COMMITTER_EMAIL]
            end

            def git_commit_committer_date
              env[Git::ENV_COMMIT_COMMITTER_DATE]
            end

            def git_pull_request_base_branch
              env[Git::ENV_PULL_REQUEST_BASE_BRANCH]
            end

            def git_pull_request_base_branch_sha
              env[Git::ENV_PULL_REQUEST_BASE_BRANCH_SHA]
            end

            def git_commit_head_sha
              env[Git::ENV_COMMIT_HEAD_SHA]
            end

            private

            def datadog_git_configuration
              config = Datadog.configuration
              config.git if config.respond_to?(:git)
            end
          end
        end
      end
    end
  end
end
