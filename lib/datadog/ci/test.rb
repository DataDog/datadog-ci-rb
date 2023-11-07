# frozen_string_literal: true

require_relative "span"

module Datadog
  module CI
    class Test < Span
      def finish
        super

        CI.deactivate_test(self)
      end

      def name
        get_tag(Ext::Test::TAG_NAME)
      end
    end
  end
end
