# frozen_string_literal: true

require_relative "concurrent_span"
require_relative "ext/test"

module Datadog
  module CI
    # Represents the whole test session process.
    # Documentation on test sessions is here:
    # https://docs.datadoghq.com/continuous_integration/explorer/?tab=testruns#sessions
    # This object can be shared between multiple threads.
    #
    # @public_api
    class TestSession < ConcurrentSpan
      # Finishes the current test session.
      # @return [void]
      def finish
        super

        recorder.deactivate_test_session
      end

      # Return the test session's name which is equal to test command used
      # @return [String] the command for this test session.
      def name
        get_tag(Ext::Test::TAG_COMMAND)
      end

      # Return the test session tags that could be inherited by sub-spans
      # @return [Hash] the tags to be inherited by sub-spans.
      def inheritable_tags
        return @inheritable_tags if defined?(@inheritable_tags)

        # this method is not synchronized because it does not iterate over the tags collection, but rather
        # uses synchronized method #get_tag to get each tag value
        res = {}
        Ext::Test::INHERITABLE_TAGS.each do |tag|
          res[tag] = get_tag(tag)
        end
        @inheritable_tags = res.freeze
      end
    end
  end
end
