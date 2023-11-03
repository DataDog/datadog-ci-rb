# frozen_string_literal: true

require_relative "ci/version"

require "datadog/core"

module Datadog
  # Datadog CI visibility public API.
  #
  # @public_api
  module CI
    class << self
      # Trace a test run
      # @public_api
      def trace_test(test_name, service_name: nil, operation_name: "test", tags: {}, &block)
        recorder.trace_test(test_name, service_name: service_name, operation_name: operation_name, tags: tags, &block)
      end

      # Start a test run trace.
      # @public_api
      def start_test(test_name, service_name: nil, operation_name: "test", tags: {})
        recorder.trace_test(test_name, service_name: service_name, operation_name: operation_name, tags: tags)
      end

      def trace(span_type, span_name, tags: {}, &block)
        recorder.trace(span_type, span_name, tags: tags, &block)
      end

      private

      def components
        Datadog.send(:components)
      end

      def recorder
        components.ci_recorder
      end
    end
  end
end

# Integrations
require_relative "ci/contrib/cucumber/integration"
require_relative "ci/contrib/rspec/integration"
require_relative "ci/contrib/minitest/integration"

# Extensions
require_relative "ci/extensions"
Datadog::CI::Extensions.activate!
