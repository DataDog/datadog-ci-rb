# frozen_string_literal: true

require "datadog/ci/utils/internal_logging"

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
          ci_provider_tags = Environment::Extractor.new(env).tags
          user_provided_tags = Environment::Extractor.new(env, provider_klass: Providers::UserDefinedTags).tags
          tags = ci_provider_tags.merge(user_provided_tags)

          local_git_tags = extract_local_git_tags(env, ci_provider_tags, user_provided_tags)
          apply_local_git_tags!(tags, ci_provider_tags, local_git_tags)

          collected_sha = local_git_tags[Git::TAG_COMMIT_SHA] || ci_provider_tags[Git::TAG_COMMIT_SHA]
          apply_user_provided_tags!(tags, user_provided_tags, collected_sha: collected_sha)

          discrepancy_checker = ConfigurationDiscrepancyChecker.new(ci_provider_tags, local_git_tags, user_provided_tags)
          discrepancy_checker.check_for_discrepancies

          ensure_post_conditions(tags)
          tags
        end

        private_class_method :extract_tags

        def extract_local_git_tags(env, ci_provider_tags, user_provided_tags)
          checkout_root = CI::Git::LocalRepository.git_root
          workspace_path = ci_provider_tags[TAG_WORKSPACE_PATH]
          custom_checkout = custom_checkout?(checkout_root, workspace_path)

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
          local_git_tags
        end

        private_class_method :extract_local_git_tags

        def custom_checkout?(checkout_root, workspace_path)
          return false unless checkout_root && workspace_path

          canonical_path(checkout_root) != canonical_path(workspace_path)
        end

        private_class_method :custom_checkout?

        def apply_local_git_tags!(tags, ci_provider_tags, local_git_tags)
          if local_git_tags[Git::TAG_COMMIT_SHA]
            # Keep workflow PR relationships when replacing the checkout identity.
            tags.delete_if do |key, _|
              key.start_with?("git.") && !key.start_with?("git.commit.head.", "git.pull_request.")
            end

            if matching_detached_checkout?(ci_provider_tags, local_git_tags)
              # A matching detached checkout can use a transport mirror. Retain its CI identity.
              [Git::TAG_BRANCH, Git::TAG_TAG, Git::TAG_REPOSITORY_URL].each do |key|
                tags[key] = ci_provider_tags[key] if ci_provider_tags[key]
              end
            end
          end
          local_git_tags.each { |key, value| tags[key] ||= value }
        end

        private_class_method :apply_local_git_tags!

        def matching_detached_checkout?(ci_provider_tags, local_git_tags)
          return false unless local_git_tags[Git::TAG_CHECKOUT_ROOT] && ci_provider_tags[TAG_WORKSPACE_PATH]
          return false if local_git_tags[Git::TAG_CHECKOUT_IS_CUSTOM] || local_git_tags[Git::TAG_BRANCH]

          ci_revisions = [
            ci_provider_tags[Git::TAG_COMMIT_SHA],
            ci_provider_tags[TAG_GIT_MERGE_COMMIT_SHA],
            ci_provider_tags[Git::TAG_COMMIT_HEAD_SHA]
          ]
          ci_revisions.include?(local_git_tags[Git::TAG_COMMIT_SHA])
        end

        private_class_method :matching_detached_checkout?

        def apply_user_provided_tags!(tags, user_provided_tags, collected_sha:)
          user_sha = user_provided_tags[Git::TAG_COMMIT_SHA]
          if user_sha && user_sha != collected_sha
            # An explicit revision must not inherit details from a different commit.
            tags.delete_if do |key, _|
              key == Git::TAG_TAG ||
                (key.start_with?("git.commit.") && key != Git::TAG_COMMIT_SHA && !key.start_with?("git.commit.head."))
            end
          end
          tags.merge!(user_provided_tags)
        end

        private_class_method :apply_user_provided_tags!

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

          Utils::InternalLogging.error("DD_GIT_REPOSITORY_URL is not set or empty; no repo URL was automatically extracted")
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

          Utils::InternalLogging.error(message)
        end
      end
    end
  end
end
