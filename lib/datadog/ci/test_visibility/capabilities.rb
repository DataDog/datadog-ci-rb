# frozen_string_literal: true

require_relative "../ext/test"

module Datadog
  module CI
    module TestVisibility
      # Generates internal tags for library capabilities
      module Capabilities
        def self.tags
          tags = {}

          test_optimisation = Datadog::CI.send(:test_optimisation)
          tags[Ext::Test::LibraryCapabilities::TAG_TEST_IMPACT_ANALYSIS] = test_optimisation.enabled.to_s

          test_management = Datadog::CI.send(:test_management)
          test_management_tag_value = test_management.enabled.to_s

          [
            Ext::Test::LibraryCapabilities::TAG_TEST_MANAGEMENT_ATTEMPT_TO_FIX,
            Ext::Test::LibraryCapabilities::TAG_TEST_MANAGEMENT_QUARATINE,
            Ext::Test::LibraryCapabilities::TAG_TEST_MANAGEMENT_DISABLE
          ].each do |tag|
            tags[tag] = test_management_tag_value
          end

          test_retries = Datadog::CI.send(:test_retries)
          tags[Ext::Test::LibraryCapabilities::TAG_AUTO_TEST_RETRIES] = test_retries.auto_test_retries_feature_enabled.to_s
          tags[Ext::Test::LibraryCapabilities::TAG_EARLY_FLAKE_DETECTION] = test_retries.early_flake_detection_feature_enabled.to_s

          tags
        end
      end
    end
  end
end
