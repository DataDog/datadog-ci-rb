# frozen_string_literal: true

require "datadog/core/utils/url"

require_relative "../git"
require_relative "../../utils/git"
require_relative "providers"

module Datadog
  module CI
    module Ext
      module Environment
        # Provider is a specific CI provider like Azure Pipelines, Github Actions, Gitlab CI, etc
        # Extractor is responsible for detecting where pipeline is being executed based on environment vars
        # and return the specific extractor that is able to return environment- and git-specific tags
        class Extractor
          def initialize(env, provider_klass: nil)
            @env = env
            @provider = provider_klass ? provider_klass.new(env) : Providers.for_environment(env)
          end

          def tags
            return @tags if defined?(@tags)

            @tags = {
              Environment::TAG_JOB_ID => @provider.job_id,
              Environment::TAG_JOB_NAME => @provider.job_name,
              Environment::TAG_JOB_URL => @provider.job_url,
              Environment::TAG_PIPELINE_ID => @provider.pipeline_id,
              Environment::TAG_PIPELINE_NAME => @provider.pipeline_name,
              Environment::TAG_PIPELINE_NUMBER => @provider.pipeline_number,
              Environment::TAG_PIPELINE_URL => @provider.pipeline_url,
              Environment::TAG_PROVIDER_NAME => @provider.provider_name,
              Environment::TAG_STAGE_NAME => @provider.stage_name,
              Environment::TAG_WORKSPACE_PATH => @provider.workspace_path,
              Environment::TAG_NODE_LABELS => @provider.node_labels,
              Environment::TAG_NODE_NAME => @provider.node_name,
              Environment::TAG_CI_ENV_VARS => @provider.ci_env_vars,

              Git::TAG_REPOSITORY_URL => @provider.git_repository_url,
              Git::TAG_BRANCH => @provider.git_branch,
              Git::TAG_TAG => @provider.git_tag,

              Git::TAG_COMMIT_SHA => @provider.git_commit_sha,
              Git::TAG_COMMIT_MESSAGE => @provider.git_commit_message,
              Git::TAG_COMMIT_AUTHOR_DATE => @provider.git_commit_author_date,
              Git::TAG_COMMIT_AUTHOR_EMAIL => @provider.git_commit_author_email,
              Git::TAG_COMMIT_AUTHOR_NAME => @provider.git_commit_author_name,
              Git::TAG_COMMIT_COMMITTER_DATE => @provider.git_commit_committer_date,
              Git::TAG_COMMIT_COMMITTER_EMAIL => @provider.git_commit_committer_email,
              Git::TAG_COMMIT_COMMITTER_NAME => @provider.git_commit_committer_name,

              Git::TAG_PULL_REQUEST_BASE_BRANCH => @provider.git_pull_request_base_branch,
              Git::TAG_PULL_REQUEST_BASE_BRANCH_SHA => @provider.git_pull_request_base_branch_sha,
              Git::TAG_PULL_REQUEST_BASE_BRANCH_HEAD_SHA => @provider.git_pull_request_base_branch_head_sha,
              Environment::TAG_PR_NUMBER => @provider.pr_number,

              Git::TAG_COMMIT_HEAD_SHA => @provider.git_commit_head_sha,
              Git::TAG_COMMIT_HEAD_MESSAGE => @provider.git_commit_head_message,
              Git::TAG_COMMIT_HEAD_AUTHOR_DATE => @provider.git_commit_head_author_date,
              Git::TAG_COMMIT_HEAD_AUTHOR_EMAIL => @provider.git_commit_head_author_email,
              Git::TAG_COMMIT_HEAD_AUTHOR_NAME => @provider.git_commit_head_author_name,
              Git::TAG_COMMIT_HEAD_COMMITTER_DATE => @provider.git_commit_head_committer_date,
              Git::TAG_COMMIT_HEAD_COMMITTER_EMAIL => @provider.git_commit_head_committer_email,
              Git::TAG_COMMIT_HEAD_COMMITTER_NAME => @provider.git_commit_head_committer_name
            }

            # Normalize Git references and filter sensitive data
            normalize_git!
            # Expand ~
            expand_workspace!

            # Convert all tag values to strings
            @tags.transform_values! { |v| v&.to_s }

            # remove empty tags
            @tags.reject! do |_, v|
              # setting type of v here to untyped because steep does not
              # understand `v.nil? || something`

              # @type var v: untyped
              v.nil? || v.to_s.strip.empty?
            end

            @tags
          end

          private

          def normalize_git!
            branch_ref = @tags[Git::TAG_BRANCH]
            if Utils::Git.is_git_tag?(branch_ref)
              @tags[Git::TAG_TAG] = branch_ref
              @tags.delete(Git::TAG_BRANCH)
            end

            @tags[Git::TAG_TAG] = Utils::Git.normalize_ref(@tags[Git::TAG_TAG])
            @tags[Git::TAG_BRANCH] = Utils::Git.normalize_ref(@tags[Git::TAG_BRANCH])
            @tags[Git::TAG_PULL_REQUEST_BASE_BRANCH] = Utils::Git.normalize_ref(@tags[Git::TAG_PULL_REQUEST_BASE_BRANCH])
            @tags[Git::TAG_REPOSITORY_URL] = Datadog::Core::Utils::Url.filter_basic_auth(
              @tags[Git::TAG_REPOSITORY_URL]
            )
          end

          def expand_workspace!
            workspace_path = @tags[TAG_WORKSPACE_PATH]

            if !workspace_path.nil? && (workspace_path == "~" || workspace_path.start_with?("~/"))
              @tags[TAG_WORKSPACE_PATH] = File.expand_path(workspace_path)
            end
          end
        end
      end
    end
  end
end
