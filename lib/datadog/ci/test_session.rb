# frozen_string_literal: true

require_relative "span"

module Datadog
  module CI
    # Represents the whole test session process.
    # This object can be shared between multiple threads.
    #
    # @public_api
    class TestSession < Span
      def initialize(tracer_span)
        super

        @mutex = Mutex.new
      end

      # Finishes the current test session.
      # @return [void]
      def finish
        super

        CI.deactivate_test_session
      end
    end
  end
end
