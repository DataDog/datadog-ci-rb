# frozen_string_literal: true

require_relative "test_session"

module Datadog
  module CI
    # @internal_api
    class ReadonlyTestSession < TestSession
      def initialize(test_session)
        @id = test_session.id
        @name = test_session.name
        @inheritable_tags = test_session.inheritable_tags
      end

      attr_reader :id, :name, :inheritable_tags

      def finish
        raise "ReadonlyTestSession cannot be finished"
      end

      def set_tag(key, value)
        raise "ReadonlyTestSession cannot be modified"
      end

      def set_metric(key, value)
        raise "ReadonlyTestSession cannot be modified"
      end
    end
  end
end
