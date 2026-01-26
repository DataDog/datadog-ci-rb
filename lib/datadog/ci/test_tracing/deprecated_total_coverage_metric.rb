# frozen_string_literal: true

require_relative "../ext/test"

module Datadog
  module CI
    module TestTracing
      module DeprecatedTotalCoverageMetric
        def self.extract_lines_pct(test_session)
          unless defined?(::SimpleCov)
            Datadog.logger.debug("SimpleCov is not loaded, skipping code coverage extraction")
            return
          end

          unless ::SimpleCov.running
            Datadog.logger.debug("SimpleCov is not running, skipping code coverage extraction")
            return
          end

          unless ::SimpleCov.respond_to?(:__dd_peek_result)
            Datadog.logger.debug("SimpleCov is not patched, skipping code coverage extraction")
            return
          end

          result = ::SimpleCov.__dd_peek_result
          unless result
            Datadog.logger.debug("SimpleCov result is nil, skipping code coverage extraction")
            return
          end

          test_session.set_tag(Ext::Test::TAG_CODE_COVERAGE_LINES_PCT, result.covered_percent)
        end
      end
    end
  end
end
