# frozen_string_literal: true

require "datadog/core/telemetry/logging"

require_relative "git"
require_relative "environment/configuration_discrepancy_checker"
require_relative "environment/extractor"

require_relative "../utils/git"

module Datadog
  module CI
    module Ext
      # Defines constants for CI tags
      module Environment
        TAG_JOB_ID = "ci.job.id"
        TAG_JOB_NAME = "ci.job.name"
        TAG_JOB_URL = "ci.job.url"
        TAG_PIPELINE_ID = "ci.pipeline.id"
        TAG_PIPELINE_NAME = "ci.pipeline.name"
        TAG_PIPELINE_DISPLAY_NAME = "ci.pipeline.display_name"
        TAG_PIPELINE_NUMBER = "ci.pipeline.number"
        TAG_PIPELINE_URL = "ci.pipeline.url"
        TAG_PROVIDER_NAME = "ci.provider.name"
        TAG_STAGE_NAME = "ci.stage.name"
        TAG_WORKSPACE_PATH = "ci.workspace_path"
        TAG_GIT_MERGE_COMMIT_SHA = "ci.git.merge_commit_sha"
        TAG_NODE_LABELS = "ci.node.labels"
        TAG_NODE_NAME = "ci.node.name"
        TAG_CI_ENV_VARS = "_dd.ci.env_vars"
        TAG_PR_NUMBER = "pr.number"

        module Provider
          APPVEYOR = "appveyor"
          AZURE = "azurepipelines"
          AWS = "awscodepipeline"
          BITBUCKET = "bitbucket"
          BITRISE = "bitrise"
          BUDDYCI = "buddy"
          BUILDKITE = "buildkite"
          CIRCLECI = "circleci"
          CODEFRESH = "codefresh"
          DRONE = "drone"
          GITHUB = "github"
          GITLAB = "gitlab"
          JENKINS = "jenkins"
          TEAMCITY = "teamcity"
          TRAVISCI = "travisci"
        end

        POSSIBLE_BUNDLE_LOCATIONS = %w[vendor/bundle .bundle].freeze

        ENV_SPECIAL_KEY_FOR_GIT_COMMIT_HEAD_SHA = "_dd.ci.environment.git_commit_head_sha"

        module_function

        def tags(env)
          @tags ||= extract_tags(env).freeze
        end

        def reset!
          @tags = nil
        end

        def extract_tags(env)
          # Extract metadata from CI provider environment variables
          ci_provider_tags = Environment::Extractor.new(env).tags

          # If user defined metadata is defined, overwrite
          user_provided_tags = Environment::Extractor.new(env, provider_klass: Providers::UserDefinedTags).tags
          tags = ci_provider_tags.merge(user_provided_tags)

          checkout_root = CI::Git::LocalRepository.git_root
          workspace_path = ci_provider_tags[TAG_WORKSPACE_PATH]
          custom_checkout = checkout_root && workspace_path &&
            canonical_path(checkout_root) != canonical_path(workspace_path)

          # Workflow PR revisions can belong to a different repository than the checkout.
          head_commit_sha = user_provided_tags[Git::TAG_COMMIT_HEAD_SHA] ||
            (ci_provider_tags[Git::TAG_COMMIT_HEAD_SHA] unless custom_checkout)
          if head_commit_sha && CI::Git::LocalRepository.git_shallow_clone?
            CI::Git::LocalRepository.fetch_head_commit_sha(head_commit_sha)
          end

          local_env = env.to_h.merge(ENV_SPECIAL_KEY_FOR_GIT_COMMIT_HEAD_SHA => head_commit_sha)
          local_git_tags = Environment::Extractor.new(local_env, provider_klass: Providers::LocalGit).tags
          local_git_tags[Git::TAG_CHECKOUT_ROOT] = checkout_root if checkout_root
          local_git_tags[Git::TAG_CHECKOUT_IS_CUSTOM] = "true" if custom_checkout
          if local_git_tags[Git::TAG_COMMIT_SHA]
            tags.delete_if do |key, _|
              key.start_with?("git.") && !key.start_with?("git.commit.head.", "git.pull_request.")
            end
            matched_revision = [ci_provider_tags[Git::TAG_COMMIT_SHA], ci_provider_tags[TAG_GIT_MERGE_COMMIT_SHA]]
              .include?(local_git_tags[Git::TAG_COMMIT_SHA])
            if checkout_root && workspace_path && !custom_checkout && !local_git_tags[Git::TAG_BRANCH] && matched_revision
              # CI supplies canonical identity for a matching detached checkout using a transport mirror.
              [Git::TAG_BRANCH, Git::TAG_TAG, Git::TAG_REPOSITORY_URL].each do |key|
                tags[key] = ci_provider_tags[key] if ci_provider_tags[key]
              end
            end
          end
          local_git_tags.each { |key, value| tags[key] ||= value }
          user_sha = user_provided_tags[Git::TAG_COMMIT_SHA]
          collected_sha = local_git_tags[Git::TAG_COMMIT_SHA] || ci_provider_tags[Git::TAG_COMMIT_SHA]
          if user_sha && user_sha != collected_sha
            tags.delete_if do |key, _|
              key == Git::TAG_TAG ||
                (key.start_with?("git.commit.") && key != Git::TAG_COMMIT_SHA && !key.start_with?("git.commit.head."))
            end
          end
          tags.merge!(user_provided_tags)

          # send some telemetry for the cases where git commit sha is overriden
          discrepancy_checker = ConfigurationDiscrepancyChecker.new(ci_provider_tags, local_git_tags, user_provided_tags)
          discrepancy_checker.check_for_discrepancies

          ensure_post_conditions(tags)

          tags
        end

        private_class_method :extract_tags

        def canonical_path(path)
          File.realpath(path)
        rescue SystemCallError, ArgumentError
          File.absolute_path(path)
        end

        private_class_method :canonical_path

        def ensure_post_conditions(tags)
          validate_repository_url(tags[Git::TAG_REPOSITORY_URL])
          validate_git_sha(tags[Git::TAG_COMMIT_SHA])
        end

        def validate_repository_url(repo_url)
          return if !repo_url.nil? && !repo_url.empty?

          Datadog.logger.error("DD_GIT_REPOSITORY_URL is not set or empty; no repo URL was automatically extracted")
          Core::Telemetry::Logger.error("DD_GIT_REPOSITORY_URL is not set or empty; no repo URL was automatically extracted")
        end

        def validate_git_sha(git_sha)
          return if Utils::Git.valid_commit_sha?(git_sha)

          message = "DD_GIT_COMMIT_SHA must be a full-length git SHA."

          message += if git_sha.nil? || git_sha.empty?
            " No value was set and no SHA was automatically extracted."
          elsif git_sha.length < Git::SHA_LENGTH
            " Expected SHA length #{Git::SHA_LENGTH}, was #{git_sha.length}."
          else
            " Expected SHA to be a valid HEX number, got #{git_sha}."
          end

          Datadog.logger.error(message)
          Core::Telemetry::Logger.error(message)
        end
      end
    end
  end
end
