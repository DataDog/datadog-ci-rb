# frozen_string_literal: true

require_relative "../ext/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module ImpactedTestsDetection
      module Telemetry
        def self.impacted_test_detected
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_IMPACTED_TESTS_IS_MODIFIED, 1)
        end
      end
    end
  end
end
