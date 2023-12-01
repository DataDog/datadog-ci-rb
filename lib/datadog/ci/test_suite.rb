# frozen_string_literal: true

require_relative "concurrent_span"

module Datadog
  module CI
    # Represents a single test suite.
    #
    # Read here on what test suite means:
    # https://docs.datadoghq.com/continuous_integration/explorer/?tab=testruns#suite
    #
    # This object can be shared between multiple threads.
    #
    # @public_api
    class TestSuite < ConcurrentSpan
      # Finishes this test suite.
      # @return [void]
      def finish
        super

        CI.deactivate_test_suite(name)
      end
    end
  end
end
