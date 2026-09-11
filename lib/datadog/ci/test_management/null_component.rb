# frozen_string_literal: true

require_relative "../ext/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module TestManagement
      class NullComponent
        FILE_STORAGE_KEY = "test_management_component_state"

        attr_reader :enabled, :tests_properties

        def initialize
          @enabled = false
          @tests_properties = {}
        end

        def configure(_, _)
        end

        def tag_test_from_properties(_)
        end

        def attempt_to_fix?(_datadog_fqn_test_id)
          false
        end

        def disabled?(_datadog_fqn_test_id)
          false
        end

        def restore_state_from_datadog_test_runner
          false
        end

        def serialize_state
          {tests_properties: @tests_properties}
        end

        def restore_state(_state)
        end

        def storage_key
          FILE_STORAGE_KEY
        end
      end
    end
  end
end
