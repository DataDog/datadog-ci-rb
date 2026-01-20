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
        TAG_PIPELINE_NUMBER = "ci.pipeline.number"
        TAG_PIPELINE_URL = "ci.pipeline.url"
        TAG_PROVIDER_NAME = "ci.provider.name"
        TAG_STAGE_NAME = "ci.stage.name"
        TAG_WORKSPACE_PATH = "ci.workspace_path"
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
          tags = Environment::Extractor.new(env).tags

          # If user defined metadata is defined, overwrite
          user_provided_tags = Environment::Extractor.new(env, provider_klass: Providers::UserDefinedTags).tags
          tags.merge!(user_provided_tags)

          # NOTE: we need to provide head commit sha as part of the environment if it was discovered from provider.
          #
          # This info will be later used by LocalGit provider to extract commit message and user info for head commit.
          # It is useful for CI providers that run jobs on artificial merge commits instead of a head commit of a
          # feature branch.
          #
          # NOTE 2: when we discover that head commit sha exists it means that we are running on an artificial merge
          # commit created by CI provider. Most likely we also operate on a shallow clone of a repo - in this case
          # we need to unshallow at least the parent of the current merge commit to be able to extract information
          # from the real original commit.
          if tags[Git::TAG_COMMIT_HEAD_SHA]
            CI::Git::LocalRepository.fetch_head_commit_sha(tags[Git::TAG_COMMIT_HEAD_SHA]) if CI::Git::LocalRepository.git_shallow_clone?

            # This is a solution that should work for all versions of dd-trace-rb that implements config inversion.
            # A proper solution would be to add a new method []= to the ConfigHelper class, but it would not be backward compatible.
            if defined?(::Datadog::Core::Configuration::ConfigHelper) && env.is_a?(::Datadog::Core::Configuration::ConfigHelper)
              env.instance_variable_get(:@source_env)[ENV_SPECIAL_KEY_FOR_GIT_COMMIT_HEAD_SHA] = tags[Git::TAG_COMMIT_HEAD_SHA]
            else
              env[ENV_SPECIAL_KEY_FOR_GIT_COMMIT_HEAD_SHA] = tags[Git::TAG_COMMIT_HEAD_SHA]
            end
          end

          # Fill out tags from local git as fallback
          local_git_tags = Environment::Extractor.new(env, provider_klass: Providers::LocalGit).tags
          local_git_tags.each do |key, value|
            tags[key] ||= value
          end

          # send some telemetry for the cases where git commit sha is overriden
          discrepancy_checker = ConfigurationDiscrepancyChecker.new(tags, local_git_tags, user_provided_tags)
          discrepancy_checker.check_for_discrepancies

          ensure_post_conditions(tags)

          tags
        end

        private_class_method :extract_tags

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
