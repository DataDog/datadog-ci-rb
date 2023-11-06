# frozen_string_literal: true

require "datadog/tracing"

require "rbconfig"

require_relative "ext/app_types"
require_relative "ext/test"
require_relative "ext/environment"

require_relative "span"

module Datadog
  module CI
    # Common behavior for CI tests
    class Recorder
      attr_reader :environment_tags

      def initialize
        @environment_tags = Ext::Environment.tags(ENV)
      end

      # Creates a new span for a CI test
      def trace_test(test_name, service_name: nil, operation_name: "test", tags: {}, &block)
        span_options = {
          resource: test_name,
          service: service_name,
          span_type: Ext::AppTypes::TYPE_TEST
        }

        tags[Ext::Test::TAG_NAME] = test_name
        tags.merge!(environment_tags)

        create_datadog_span(operation_name, span_options: span_options, tags: tags, &block)
      end

      def trace(span_type, span_name, tags: {}, &block)
        span_options = {
          resource: span_name,
          span_type: span_type
        }

        create_datadog_span(span_name, span_options: span_options, tags: tags, &block)
      end

      private

      def create_datadog_span(span_name, span_options: {}, tags: {}, &block)
        if block
          Datadog::Tracing.trace(span_name, **span_options) do |tracer_span, trace|
            set_internal_tracing_context!(trace, tracer_span)
            block.call(Span.new(tracer_span, tags))
          end
        else
          tracer_span = Datadog::Tracing.trace(span_name, **span_options)
          trace = Datadog::Tracing.active_trace

          set_internal_tracing_context!(trace, tracer_span)
          Span.new(tracer_span, tags)
        end
      end

      def set_internal_tracing_context!(trace, span)
        # Sets trace's origin to ciapp-test
        trace.origin = Ext::Test::CONTEXT_ORIGIN if trace
      end
    end
  end
end
