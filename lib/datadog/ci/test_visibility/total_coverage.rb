# frozen_string_literal: true

require_relative "../ext/test"

module Datadog
  module CI
    module TestVisibility
      module TotalCoverage
        def self.extract_lines_pct(test_session)
          return unless defined?(::SimpleCov)
          return unless ::SimpleCov.running
          return unless ::SimpleCov.respond_to?(:__dd_peek_result)

          result = ::SimpleCov.__dd_peek_result
          return unless result

          test_session.set_tag(Ext::Test::TAG_CODE_COVERAGE_LINES_PCT, result.covered_percent)
        end
      end
    end
  end
end
