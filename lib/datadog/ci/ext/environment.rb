# frozen_string_literal: true

require_relative "git"
require_relative "environment/extractor"
require_relative "environment/user_defined_tags"
require_relative "environment/local_git"

module Datadog
  module CI
    module Ext
      # Defines constants for CI tags
      module Environment
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

        module_function

        def tags(env)
          # Extract metadata from CI provider environment variables
          tags = Environment::Extractor.for_environment(env).tags

          # If user defined metadata is defined, overwrite
          tags.merge!(
            UserDefinedTags.new(env).tags
          )

          # Fill out tags from local git as fallback
          local_git_tags = LocalGit.new(env).tags
          local_git_tags.each do |key, value|
            tags[key] ||= value
          end

          tags
        end
      end
    end
  end
end
