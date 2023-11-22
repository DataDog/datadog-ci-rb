# frozen_string_literal: true

require_relative "concurrent_span"
require_relative "ext/test"

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

      def inheritable_tags
        # this method is not synchronized because it does not iterate over the tags, but rather
        # uses synchronized method to get each tag value
        res = {}
        Ext::Test::INHERITABLE_TAGS.each do |tag|
          res[tag] = get_tag(tag)
        end
        res
      end
    end
  end
end
