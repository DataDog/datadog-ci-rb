# frozen_string_literal: true

require_relative "concurrent_span"

module Datadog
  module CI
    # Represents a single test module.
    # Read here on what test module could mean:
    # https://docs.datadoghq.com/continuous_integration/explorer/?tab=testruns#module
    # This object can be shared between multiple threads.
    #
    # @public_api
    class TestModule < ConcurrentSpan
      # Finishes this test module.
      # @return [void]
      def finish
        super

        # CI.deactivate_test_module(self)
      end
    end
  end
end
