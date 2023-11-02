# frozen_string_literal: true

require_relative "ci/version"

require "datadog/core"
require "datadog/tracing"

require_relative "ci/recorder"

module Datadog
  # Public API for Datadog CI visibility
  module CI
    class << self
      def trace_test(test_name, service_name: nil, operation_name: "test", tags: {}, &block)
        recorder.trace_test(test_name, service_name: service_name, operation_name: operation_name, tags: tags, &block)
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
