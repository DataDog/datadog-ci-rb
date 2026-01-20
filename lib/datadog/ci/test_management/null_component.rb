# frozen_string_literal: true

require_relative "../ext/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module TestManagement
      class NullComponent
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
      end
    end
  end
end
