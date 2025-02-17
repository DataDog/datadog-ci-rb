# frozen_string_literal: true

require_relative "../ext/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module TestManagement
      # Test management is a feature that lets people manage their flaky tests in Datadog.
      # It includes:
      # - marking test as quarantined causes test to continue running but not failing the build
      # - marking test as disabled causes test to be skipped
      # - marking test as "attempted to fix" causes test to be retried many times to confirm that fix worked
      class Component
        attr_reader :enabled, :tests_properties

        def initialize(
          enabled:,
          attempt_to_fix_retries_count:,
          tests_properties_client:
        )
          @enabled = enabled
          @attempt_to_fix_retries_count = attempt_to_fix_retries_count

          @tests_properties_client = tests_properties_client
          @tests_properties = {}
        end

        def configure(library_settings, test_session)
          @enabled &&= library_settings.test_management_enabled?

          return unless @enabled

          @tests_properties = @tests_properties_client.fetch(test_session)

          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_TEST_MANAGEMENT_TESTS_RESPONSE_TESTS,
            @tests_properties.count.to_f
          )
        end
      end
    end
  end
end
