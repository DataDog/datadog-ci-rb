module Datadog
  module CI
    module ImpactedTestsDetection
      module Telemetry
        def self.impacted_test_detected
          Datadog::CI::Utils::Telemetry.inc(Datadog::CI::Ext::Telemetry::METRIC_IMPACTED_TESTS_IS_MODIFIED, 1)
        end
      end
    end
  end
end
