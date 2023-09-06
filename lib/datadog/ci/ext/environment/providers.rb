# frozen_string_literal: true

require_relative "providers/base"
require_relative "providers/appveyor"
require_relative "providers/azure"
require_relative "providers/bitbucket"
require_relative "providers/bitrise"
require_relative "providers/buddy"
require_relative "providers/buildkite"
require_relative "providers/circleci"
require_relative "providers/codefresh"
require_relative "providers/github_actions"
require_relative "providers/gitlab"
require_relative "providers/jenkins"
require_relative "providers/teamcity"
require_relative "providers/travis"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          PROVIDERS = [
            ["APPVEYOR", Providers::Appveyor],
            ["TF_BUILD", Providers::Azure],
            ["BITBUCKET_COMMIT", Providers::Bitbucket],
            ["BITRISE_BUILD_SLUG", Providers::Bitrise],
            ["BUDDY", Providers::Buddy],
            ["BUILDKITE", Providers::Buildkite],
            ["CIRCLECI", Providers::Circleci],
            ["CF_BUILD_ID", Providers::Codefresh],
            ["GITHUB_SHA", Providers::GithubActions],
            ["GITLAB_CI", Providers::Gitlab],
            ["JENKINS_URL", Providers::Jenkins],
            ["TEAMCITY_VERSION", Providers::Teamcity],
            ["TRAVIS", Providers::Travis]
          ]

          def self.for_environment(env)
            _, provider_klass = PROVIDERS.find { |provider_env_var, _| env.key?(provider_env_var) }
            provider_klass = Providers::Base if provider_klass.nil?

            provider_klass.new(env)
          end
        end
      end
    end
  end
end
