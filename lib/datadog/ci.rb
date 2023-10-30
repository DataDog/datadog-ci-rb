# frozen_string_literal: true

require_relative "ci/version"

require "datadog/core"
require "datadog/tracing"

module Datadog
  # Public API for Datadog CI visibility
  module CI
    module_function

    def trace(span_type, span_name, span_options = {})
      span_options[:resource] = span_name
      span_options[:span_type] = span_type

      if block_given?
        Datadog::Tracing.trace(span_name, **span_options) do |tracer_span|
          yield Span.new(tracer_span)
        end
      else
        tracer_span = Datadog::Tracing.trace(span_name, **span_options)
        Span.new(tracer_span)
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
