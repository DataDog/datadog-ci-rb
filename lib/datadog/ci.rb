# frozen_string_literal: true

require_relative "ci/version"

require "datadog/core"
require "datadog/tracing"

require_relative "ci/recorder"
require_relative "ci/span"
require_relative "ci/test"

module Datadog
  # Public API for Datadog CI visibility
  module CI
    def self.trace_test(test_name, service_name: nil, operation_name: "test", tags: {}, &block)
      Recorder.trace_test(test_name, service_name: service_name, operation_name: operation_name, tags: tags, &block)
    end

    def self.trace(span_type, span_name, &block)
      Recorder.trace(span_type, span_name, &block)
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
