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
require_relative "null_span"
require_relative "test"
require_relative "test_session"
require_relative "test_module"
require_relative "test_suite"

module Datadog
  module CI
    # Common behavior for CI tests
    # Note: this class has too many responsibilities and should be split into multiple classes
    class Recorder
      attr_reader :environment_tags, :test_suite_level_visibility_enabled, :enabled

      def initialize(enabled: true, test_suite_level_visibility_enabled: false)
        @enabled = enabled
        @test_suite_level_visibility_enabled = enabled && test_suite_level_visibility_enabled

        @environment_tags = Ext::Environment.tags(ENV).freeze
        @local_context = Context::Local.new
        @global_context = Context::Global.new
      end

      def start_test_session(service_name: nil, tags: {})
        return skip_tracing unless test_suite_level_visibility_enabled

        tracer_span = start_datadog_tracer_span(
          "test.session", build_span_options(service_name, Ext::AppTypes::TYPE_TEST_SESSION)
        )
        set_session_context(tags, tracer_span)

        test_session = build_test_session(tracer_span, tags)
        @global_context.activate_test_session!(test_session)

        test_session
      end

      def start_test_module(test_module_name, service_name: nil, tags: {})
        return skip_tracing unless test_suite_level_visibility_enabled

        tags = tags_with_inherited_globals(tags)
        set_session_context(tags)

        tracer_span = start_datadog_tracer_span(
          test_module_name, build_span_options(service_name, Ext::AppTypes::TYPE_TEST_MODULE)
        )
        set_module_context(tags, tracer_span)

        test_module = build_test_module(tracer_span, tags)
        @global_context.activate_test_module!(test_module)

        test_module
      end

      def start_test_suite(test_suite_name, service_name: nil, tags: {})
        return skip_tracing unless test_suite_level_visibility_enabled

        @global_context.fetch_or_activate_test_suite(test_suite_name) do
          tags = tags_with_inherited_globals(tags)
          set_session_context(tags)
          set_module_context(tags)

          tracer_span = start_datadog_tracer_span(
            test_suite_name, build_span_options(service_name, Ext::AppTypes::TYPE_TEST_SUITE)
          )
          set_suite_context(tags, span: tracer_span)

          build_test_suite(tracer_span, tags)
        end
      end

      def trace_test(test_name, test_suite_name, service_name: nil, operation_name: "test", tags: {}, &block)
        return skip_tracing(block) unless enabled

        tags = tags_with_inherited_globals(tags)
        set_session_context(tags)
        set_module_context(tags)
        set_suite_context(tags, name: test_suite_name)

        tags[Ext::Test::TAG_NAME] = test_name

        span_options = build_span_options(
          service_name,
          Ext::AppTypes::TYPE_TEST,
          # :resource is needed for the agent APM protocol to work correctly (for older agent versions)
          # :continue_from is required to start a new trace for each test
          {resource: test_name, continue_from: Datadog::Tracing::TraceDigest.new}
        )

        if block
          start_datadog_tracer_span(operation_name, span_options) do |tracer_span|
            test = build_test(tracer_span, tags)

            @local_context.activate_test!(test) do
              block.call(test)
            end
          end
        else
          tracer_span = start_datadog_tracer_span(operation_name, span_options)

          test = build_test(tracer_span, tags)
          @local_context.activate_test!(test)
          test
        end
      end

      def trace(span_type, span_name, tags: {}, &block)
        return skip_tracing(block) unless enabled

        span_options = build_span_options(
          nil, # service name is completely optional for custom spans
          span_type,
          {resource: span_name}
        )

        if block
          start_datadog_tracer_span(span_name, span_options) do |tracer_span|
            block.call(build_span(tracer_span, tags))
          end
        else
          tracer_span = start_datadog_tracer_span(span_name, span_options)

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

      def active_test_module
        @global_context.active_test_module
      end

      def active_test_suite(test_suite_name)
        @global_context.active_test_suite(test_suite_name)
      end

      # TODO: does it make sense to have a parameter here?
      def deactivate_test(test)
        @local_context.deactivate_test!(test)
      end

      def deactivate_test_session
        @global_context.deactivate_test_session!
      end

      def deactivate_test_module
        @global_context.deactivate_test_module!
      end

      def deactivate_test_suite(test_suite_name)
        @global_context.deactivate_test_module!
      end

      private

      def skip_tracing(block = nil)
        if block
          block.call(null_span)
        else
          null_span
        end
      end

      # Sets trace's origin to ciapp-test
      def set_trace_origin(trace)
        trace.origin = Ext::Test::CONTEXT_ORIGIN if trace
      end

      def build_test_session(tracer_span, tags)
        test_session = TestSession.new(tracer_span)
        set_initial_tags(test_session, tags)
        test_session
      end

      def build_test_module(tracer_span, tags)
        test_module = TestModule.new(tracer_span)
        set_initial_tags(test_module, tags)
        test_module
      end

      def build_test_suite(tracer_span, tags)
        test_suite = TestSuite.new(tracer_span)
        set_initial_tags(test_suite, tags)
        test_suite
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

      def build_span_options(service_name, span_type, other_options = {})
        other_options[:service] = service_name || @global_context.service
        other_options[:span_type] = span_type

        other_options
      end

      def tags_with_inherited_globals(tags)
        @global_context.inheritable_session_tags.merge(tags)
      end

      def set_initial_tags(ci_span, tags)
        ci_span.set_default_tags
        ci_span.set_environment_runtime_tags

        ci_span.set_tags(tags)
        ci_span.set_tags(environment_tags)
      end

      def set_session_context(tags, test_session = nil)
        test_session ||= active_test_session
        tags[Ext::Test::TAG_TEST_SESSION_ID] = test_session.id if test_session
      end

      def set_module_context(tags, test_module = nil)
        test_module ||= active_test_module
        if test_module
          tags[Ext::Test::TAG_TEST_MODULE_ID] = test_module.id
          tags[Ext::Test::TAG_MODULE] = test_module.name
        end
      end

      def set_suite_context(tags, span: nil, name: nil)
        return if span.nil? && name.nil?

        test_suite = span || active_test_suite(name)

        if test_suite
          tags[Ext::Test::TAG_TEST_SUITE_ID] = test_suite.id
          tags[Ext::Test::TAG_SUITE] = test_suite.name
        else
          tags[Ext::Test::TAG_SUITE] = name
        end
      end

      def start_datadog_tracer_span(span_name, span_options, &block)
        if block
          Datadog::Tracing.trace(span_name, **span_options) do |tracer_span, trace|
            set_trace_origin(trace)

            yield tracer_span
          end
        else
          tracer_span = Datadog::Tracing.trace(span_name, **span_options)
          trace = Datadog::Tracing.active_trace
          set_trace_origin(trace)

          tracer_span
        end
      end

      def null_span
        @null_span ||= NullSpan.new
      end
    end
  end
end
