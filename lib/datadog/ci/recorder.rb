# frozen_string_literal: true

require "datadog/tracing"
require "datadog/tracing/contrib/analytics"

require_relative "ext/app_types"
require_relative "ext/test"
require_relative "ext/environment"

require_relative "span"

require "rbconfig"

module Datadog
  module CI
    # Common behavior for CI tests
    module Recorder
      # Creates a new span for a CI test
      def self.trace_test(test_name, service_name: nil, operation_name: "test", tags: {}, &block)
        span_options = {
          resource: test_name,
          service: service_name,
          span_type: Ext::AppTypes::TYPE_TEST
        }

        tags[Ext::Test::TAG_NAME] = test_name
        tags.merge!(environment_tags)

        if block
          ::Datadog::Tracing.trace(operation_name, **span_options) do |tracer_span, trace|
            set_internal_tracing_context!(trace, tracer_span)
            block.call(Span.new(tracer_span, tags))
          end
        else
          tracer_span = ::Datadog::Tracing.trace(operation_name, **span_options)
          trace = ::Datadog::Tracing.active_trace

          set_internal_tracing_context!(trace, tracer_span)
          Span.new(tracer_span, tags)
        end
      end

      def self.trace(span_type, span_name, tags: {}, &block)
        span_options = {
          resource: span_name,
          span_type: span_type
        }

        if block
          ::Datadog::Tracing.trace(span_name, **span_options) do |tracer_span|
            block.call(Span.new(tracer_span, tags))
          end
        else
          tracer_span = Datadog::Tracing.trace(span_name, **span_options)
          Span.new(tracer_span, tags)
        end
      end

      def self.set_internal_tracing_context!(trace, span)
        # Set default tags
        trace.origin = Ext::Test::CONTEXT_ORIGIN if trace
        ::Datadog::Tracing::Contrib::Analytics.set_measured(span)
      end

      def self.environment_tags
        @environment_tags ||= Ext::Environment.tags(ENV)
      end
    end
  end
end
