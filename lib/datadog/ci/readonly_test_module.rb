# frozen_string_literal: true

require_relative "test_module"

module Datadog
  module CI
    # @internal_api
    class ReadonlyTestModule < TestModule
      def initialize(test_module)
        @id = test_module.id
        @name = test_module.name
      end
      attr_reader :id, :name

      def finish
        raise "ReadonlyTestModule cannot be finished"
      end

      def set_tag(key, value)
        raise "ReadonlyTestModule cannot be modified"
      end

      def set_metric(key, value)
        raise "ReadonlyTestModule cannot be modified"
      end
    end
  end
end
