# frozen_string_literal: true

require_relative "../ext/telemetry"
require_relative "../ext/test"
require_relative "../utils/telemetry"
require_relative "../test_tracing/telemetry"

module Datadog
  module CI
    module TestImpactAnalysis
      # Telemetry for test impact analysis component
      module Telemetry
        def self.code_coverage_started(test)
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_CODE_COVERAGE_STARTED, 1, tags_for_test(test))
        end

        def self.code_coverage_finished(test)
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_CODE_COVERAGE_FINISHED, 1, tags_for_test(test))
        end

        def self.code_coverage_is_empty
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_CODE_COVERAGE_IS_EMPTY, 1)
        end

        def self.code_coverage_files(count)
          Utils::Telemetry.distribution(Ext::Telemetry::METRIC_CODE_COVERAGE_FILES, count.to_f)
        end

        def self.itr_skipped
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_ITR_SKIPPED, 1, tags_for_itr_metrics)
        end

        def self.itr_forced_run
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_ITR_FORCED_RUN, 1, tags_for_itr_metrics)
        end

        def self.itr_unskippable
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_ITR_UNSKIPPABLE, 1, tags_for_itr_metrics)
        end

        def self.tags_for_test(test)
          {
            Ext::Telemetry::TAG_TEST_FRAMEWORK => test.get_tag(Ext::Test::TAG_FRAMEWORK),
            Ext::Telemetry::TAG_LIBRARY => Ext::Telemetry::Library::CUSTOM
          }
        end

        def self.tags_for_itr_metrics
          {
            Ext::Telemetry::TAG_EVENT_TYPE => Ext::Telemetry::EventType::TEST
          }
        end
      end
    end
  end
end
