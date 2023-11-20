# frozen_string_literal: true

require "datadog/tracing"

require "rbconfig"

require_relative "ext/app_types"
require_relative "ext/test"
require_relative "ext/environment"

require_relative "context/local"

require_relative "span"
require_relative "test"

module Datadog
  module CI
    # Common behavior for CI tests
    class Recorder
      attr_reader :environment_tags

      def initialize
        @environment_tags = Ext::Environment.tags(ENV).freeze
        @local_context = Context::Local.new
      end

      # Creates a new span for a CI test
      def trace_test(test_name, service_name: nil, operation_name: "test", tags: {}, &block)
        span_options = {
          resource: test_name,
          service: service_name,
          span_type: Ext::AppTypes::TYPE_TEST
        }

        tags[Ext::Test::TAG_NAME] = test_name

        if block
          Datadog::Tracing.trace(operation_name, **span_options) do |tracer_span, trace|
            set_trace_origin(trace)

            test = build_test(tracer_span, tags)

            @local_context.activate_test!(test) do
              block.call(test)
            end
          end
        else
          tracer_span = Datadog::Tracing.trace(operation_name, **span_options)
          trace = Datadog::Tracing.active_trace

          set_trace_origin(trace)

          test = build_test(tracer_span, tags)
          @local_context.activate_test!(test)
          test
        end
      end

      def trace(span_type, span_name, tags: {}, &block)
        span_options = {
          resource: span_name,
          span_type: span_type
        }

        if block
          Datadog::Tracing.trace(span_name, **span_options) do |tracer_span, trace|
            block.call(build_span(tracer_span, tags))
          end
        else
          tracer_span = Datadog::Tracing.trace(span_name, **span_options)

          build_span(tracer_span, tags)
        end
      end

      def active_test
        @local_context.active_test
      end

      def deactivate_test(test)
        @local_context.deactivate_test!(test)
      end

      def active_span
        tracer_span = Datadog::Tracing.active_span
        Span.new(tracer_span) if tracer_span
      end

      private

      # Sets trace's origin to ciapp-test
      def set_trace_origin(trace)
        trace.origin = Ext::Test::CONTEXT_ORIGIN if trace
      end

      def build_test(tracer_span, tags)
        test = Test.new(tracer_span)

        test.set_default_tags
        test.set_environment_runtime_tags

        test.set_tags(tags)
        test.set_tags(environment_tags)

        test
      end

      def build_span(tracer_span, tags)
        span = Span.new(tracer_span)

        span.set_default_tags
        span.set_environment_runtime_tags
        span.set_tags(tags)

        span
      end
    end
  end
end
