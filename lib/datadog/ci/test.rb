# frozen_string_literal: true

require_relative "span"

module Datadog
  module CI
    # Represents a single part of a test run.
    # Could be a session, suite, test, or any custom span.
    #
    # @public_api
    class Test < Span
      # @return [String] the name of the test.
      def name
        get_tag(Ext::Test::TAG_NAME)
      end

      # Finishes the current test.
      # @return [void]
      def finish
        super

        CI.deactivate_test(self)
      end
    end
  end
end
