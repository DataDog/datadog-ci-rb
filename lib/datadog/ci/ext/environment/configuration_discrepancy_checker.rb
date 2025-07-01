# frozen_string_literal: true

require_relative "../git"
require_relative "../telemetry"
require_relative "../../utils/telemetry"

module Datadog
  module CI
    module Ext
      module Environment
        class ConfigurationDiscrepancyChecker
          def initialize(ci_provider_env_tags, local_git_tags, user_provided_tags)
            @ci_provider_env_tags = ci_provider_env_tags
            @local_git_tags = local_git_tags
            @user_provided_tags = user_provided_tags
          end

          def check_for_discrepancies
            checks = [
              {
                left: normalize_value(@ci_provider_env_tags[Git::TAG_COMMIT_SHA]),
                right: normalize_value(@local_git_tags[Git::TAG_COMMIT_SHA]),
                type: "commit_discrepancy",
                expected: "ci_provider",
                discrepant: "git_client"
              },
              {
                left: normalize_value(@user_provided_tags[Git::TAG_COMMIT_SHA]),
                right: normalize_value(@local_git_tags[Git::TAG_COMMIT_SHA]),
                type: "commit_discrepancy",
                expected: "user_supplied",
                discrepant: "git_client"
              },
              {
                left: normalize_value(@user_provided_tags[Git::TAG_COMMIT_SHA]),
                right: normalize_value(@ci_provider_env_tags[Git::TAG_COMMIT_SHA]),
                type: "commit_discrepancy",
                expected: "user_supplied",
                discrepant: "ci_provider"
              },
              {
                left: normalize_value(@ci_provider_env_tags[Git::TAG_REPOSITORY_URL]),
                right: normalize_value(@local_git_tags[Git::TAG_REPOSITORY_URL]),
                type: "repository_discrepancy",
                expected: "ci_provider",
                discrepant: "git_client"
              },
              {
                left: normalize_value(@user_provided_tags[Git::TAG_REPOSITORY_URL]),
                right: normalize_value(@local_git_tags[Git::TAG_REPOSITORY_URL]),
                type: "repository_discrepancy",
                expected: "user_supplied",
                discrepant: "git_client"
              },
              {
                left: normalize_value(@user_provided_tags[Git::TAG_REPOSITORY_URL]),
                right: normalize_value(@ci_provider_env_tags[Git::TAG_REPOSITORY_URL]),
                type: "repository_discrepancy",
                expected: "user_supplied",
                discrepant: "ci_provider"
              }
            ]

            git_info_match = true
            checks.each do |check|
              if check[:left] && check[:right] && check[:left] != check[:right]
                Utils::Telemetry.inc(Ext::Telemetry::METRIC_GIT_COMMIT_SHA_DISCREPANCY, 1, {
                  type: check[:type].to_s,
                  expected_provider: check[:expected].to_s,
                  discrepant_provider: check[:discrepant].to_s
                })
                git_info_match = false
              end
            end

            Utils::Telemetry.inc(Ext::Telemetry::METRIC_GIT_COMMIT_SHA_MATCH, 1, {
              matched: git_info_match.to_s
            })
          end

          private

          def normalize_value(value)
            return nil if value.nil? || value == ""
            value
          end
        end
      end
    end
  end
end
