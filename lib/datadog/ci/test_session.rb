# frozen_string_literal: true

require_relative "concurrent_span"

module Datadog
  module CI
    # Represents the whole test session process.
    # This object can be shared between multiple threads.
    #
    # @public_api
    class TestSession < ConcurrentSpan
      # Finishes the current test session.
      # @return [void]
      def finish
        super

        CI.deactivate_test_session
      end
    end
  end
end
