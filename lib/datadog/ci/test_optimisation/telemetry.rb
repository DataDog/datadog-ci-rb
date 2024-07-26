# frozen_string_literal: true

require_relative "../ext/telemetry"
require_relative "../ext/test"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module TestOptimisation
      # Telemetry for test optimisation component
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

        def self.tags_for_test(test)
          {
            Ext::Telemetry::TAG_TEST_FRAMEWORK => test.get_tag(Ext::Test::TAG_FRAMEWORK),
            Ext::Telemetry::TAG_LIBRARY => Ext::Telemetry::Library::CUSTOM
          }
        end
      end
    end
  end
end
