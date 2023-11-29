# frozen_string_literal: true

require "datadog/tracing"
require "datadog/tracing/trace_digest"

require "rbconfig"

require_relative "ext/app_types"
require_relative "ext/test"
require_relative "ext/environment"

require_relative "context/global"
require_relative "context/local"

require_relative "span"
require_relative "test"
require_relative "test_session"

module Datadog
  module CI
    # Common behavior for CI tests
    class Recorder
      attr_reader :environment_tags, :test_suite_level_visibility_enabled

      def initialize(test_suite_level_visibility_enabled: false)
        @test_suite_level_visibility_enabled = test_suite_level_visibility_enabled

        @environment_tags = Ext::Environment.tags(ENV).freeze
        @local_context = Context::Local.new
        @global_context = Context::Global.new
      end

      def start_test_session(service_name: nil, tags: {})
        return nil unless @test_suite_level_visibility_enabled

        span_options = {
          service: service_name,
          span_type: Ext::AppTypes::TYPE_TEST_SESSION
        }

        tracer_span = Datadog::Tracing.trace("test.session", **span_options)
        trace = Datadog::Tracing.active_trace

        set_trace_origin(trace)

        tags[Ext::Test::TAG_TEST_SESSION_ID] = tracer_span.id

        test_session = build_test_session(tracer_span, tags)
        @global_context.activate_test_session!(test_session)

        test_session
      end

      # Creates a new span for a CI test
      def trace_test(test_name, service_name: nil, operation_name: "test", tags: {}, &block)
        test_session = active_test_session
        if test_session
          service_name ||= test_session.service

          tags = test_session.inheritable_tags.merge(tags)
        end

        span_options = {
          resource: test_name,
          service: service_name,
          span_type: Ext::AppTypes::TYPE_TEST,
          # this option is needed to force a new trace to be created
          continue_from: Datadog::Tracing::TraceDigest.new
        }

        tags[Ext::Test::TAG_NAME] = test_name
        tags[Ext::Test::TAG_TEST_SESSION_ID] = test_session.id if test_session

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

      def active_span
        tracer_span = Datadog::Tracing.active_span
        Span.new(tracer_span) if tracer_span
      end

      def active_test
        @local_context.active_test
      end

      def active_test_session
        @global_context.active_test_session
      end

      # TODO: does it make sense to have a parameter here?
      def deactivate_test(test)
        @local_context.deactivate_test!(test)
      end

      def deactivate_test_session
        @global_context.deactivate_test_session!
      end

      private

      # Sets trace's origin to ciapp-test
      def set_trace_origin(trace)
        trace.origin = Ext::Test::CONTEXT_ORIGIN if trace
      end

      def build_test_session(tracer_span, tags)
        test_session = TestSession.new(tracer_span)
        set_initial_tags(test_session, tags)
        test_session
      end

      def build_test(tracer_span, tags)
        test = Test.new(tracer_span)
        set_initial_tags(test, tags)
        test
      end

      def build_span(tracer_span, tags)
        span = Span.new(tracer_span)
        set_initial_tags(span, tags)
        span
      end

      def set_initial_tags(ci_span, tags)
        ci_span.set_default_tags
        ci_span.set_environment_runtime_tags

        ci_span.set_tags(tags)
        ci_span.set_tags(environment_tags)
      end
    end
  end
end
