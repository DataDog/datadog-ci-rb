# frozen_string_literal: true

require_relative "../ext/telemetry"
require_relative "../ext/test"
require_relative "../utils/stateful"
require_relative "../utils/telemetry"
require_relative "../utils/test_run"

module Datadog
  module CI
    module TestManagement
      # Test management is a feature that lets people manage their flaky tests in Datadog.
      # It includes:
      # - marking test as quarantined causes test to continue running but not failing the build
      # - marking test as disabled causes test to be skipped
      # - marking test as "attempted to fix" causes test to be retried many times to confirm that fix worked
      class Component
        include Datadog::CI::Utils::Stateful

        FILE_STORAGE_KEY = "test_management_component_state"

        attr_reader :enabled, :tests_properties

        def initialize(enabled:, tests_properties_client:)
          @enabled = enabled

          @tests_properties_client = tests_properties_client
          @tests_properties = {}
        end

        def configure(library_settings, test_session)
          @enabled &&= library_settings.test_management_enabled?

          return unless @enabled

          test_session.set_tag(Ext::Test::TAG_TEST_MANAGEMENT_ENABLED, "true")

          # Load component state first, and if successful, skip fetching tests properties
          if !load_component_state
            @tests_properties = @tests_properties_client.fetch(test_session)
            store_component_state if test_session.distributed
          end

          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_TEST_MANAGEMENT_TESTS_RESPONSE_TESTS,
            @tests_properties.count.to_f
          )
        end

        def tag_test_from_properties(test_span)
          return unless @enabled

          datadog_test_id = Utils::TestRun.datadog_test_id(test_span.name, test_span.test_suite_name)
          test_properties = @tests_properties[datadog_test_id]

          if test_properties.nil?
            Datadog.logger.debug { "Test properties not found for test: #{datadog_test_id}" }
            return
          end

          Datadog.logger.debug { "Test properties for test #{datadog_test_id} are: [#{test_properties}]" }

          test_span.set_tag(Ext::Test::TAG_IS_QUARANTINED, "true") if test_properties["quarantined"]
          test_span.set_tag(Ext::Test::TAG_IS_TEST_DISABLED, "true") if test_properties["disabled"]
          test_span.set_tag(Ext::Test::TAG_IS_ATTEMPT_TO_FIX, "true") if test_properties["attempt_to_fix"]
        end

        def attempt_to_fix?(datadog_fqn_test_id)
          return false unless @enabled

          test_properties = @tests_properties[datadog_fqn_test_id]
          return false if test_properties.nil?

          test_properties.fetch("attempt_to_fix", false)
        end

        # Implementation of Stateful interface
        def serialize_state
          {
            tests_properties: @tests_properties
          }
        end

        def restore_state(state)
          @tests_properties = state[:tests_properties]
        end

        def storage_key
          FILE_STORAGE_KEY
        end
      end
    end
  end
end
