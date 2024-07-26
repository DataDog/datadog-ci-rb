# frozen_string_literal: true

require "datadog/tracing"
require "datadog/tracing/contrib/component"
require "datadog/tracing/trace_digest"

require_relative "store/global"
require_relative "store/local"

require_relative "../ext/app_types"
require_relative "../ext/environment"
require_relative "../ext/test"

require_relative "../span"
require_relative "../test"
require_relative "../test_session"
require_relative "../test_module"
require_relative "../test_suite"

module Datadog
  module CI
    module TestVisibility
      # Manages current in-memory context for test visibility (such as active test session, suite, test, etc.).
      # Its responsibility includes building domain models for test visibility as well.
      # Internally it uses Datadog::Tracing module to create spans.
      class Context
        def initialize
          @local_context = Store::Local.new
          @global_context = Store::Global.new
        end

        def start_test_session(service: nil, tags: {})
          @global_context.fetch_or_activate_test_session do
            tracer_span = start_datadog_tracer_span(
              "test.session", build_tracing_span_options(service, Ext::AppTypes::TYPE_TEST_SESSION)
            )
            set_session_context(tags, tracer_span)

            build_test_session(tracer_span, tags)
          end
        end

        def start_test_module(test_module_name, service: nil, tags: {})
          @global_context.fetch_or_activate_test_module do
            set_inherited_globals(tags)
            set_session_context(tags)

            tracer_span = start_datadog_tracer_span(
              test_module_name, build_tracing_span_options(service, Ext::AppTypes::TYPE_TEST_MODULE)
            )
            set_module_context(tags, tracer_span)

            build_test_module(tracer_span, tags)
          end
        end

        def start_test_suite(test_suite_name, service: nil, tags: {})
          @global_context.fetch_or_activate_test_suite(test_suite_name) do
            set_inherited_globals(tags)
            set_session_context(tags)
            set_module_context(tags)

            tracer_span = start_datadog_tracer_span(
              test_suite_name, build_tracing_span_options(service, Ext::AppTypes::TYPE_TEST_SUITE)
            )
            set_suite_context(tags, span: tracer_span)

            build_test_suite(tracer_span, tags)
          end
        end

        def trace_test(test_name, test_suite_name, service: nil, tags: {}, &block)
          set_inherited_globals(tags)
          set_session_context(tags)
          set_module_context(tags)
          set_suite_context(tags, name: test_suite_name)

          tags[Ext::Test::TAG_NAME] = test_name
          tags[Ext::Test::TAG_TYPE] ||= Ext::Test::Type::TEST

          span_options = build_tracing_span_options(
            service,
            Ext::AppTypes::TYPE_TEST,
            # :resource is needed for the agent APM protocol to work correctly (for older agent versions)
            # :continue_from is required to start a new trace for each test
            {resource: test_name, continue_from: Datadog::Tracing::TraceDigest.new}
          )

          if block
            start_datadog_tracer_span(test_name, span_options) do |tracer_span|
              test = build_test(tracer_span, tags)

              @local_context.activate_test(test) do
                block.call(test)
              end
            end
          else
            tracer_span = start_datadog_tracer_span(test_name, span_options)
            test = build_test(tracer_span, tags)
            @local_context.activate_test(test)
            test
          end
        end

        def trace(span_name, type: "span", tags: {}, &block)
          span_options = build_tracing_span_options(
            nil, # service name is completely optional for custom spans
            type,
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

        def single_active_test_suite
          @global_context.fetch_single_test_suite
        end

        def deactivate_test
          @local_context.deactivate_test
        end

        def deactivate_test_session
          @global_context.deactivate_test_session!
        end

        def deactivate_test_module
          @global_context.deactivate_test_module!
        end

        def deactivate_test_suite(test_suite_name)
          @global_context.deactivate_test_suite!(test_suite_name)
        end

        private

        # BUILDING DOMAIN MODELS
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

        # TAGGING
        def set_initial_tags(ci_span, tags)
          @environment_tags ||= Ext::Environment.tags(ENV).freeze

          ci_span.set_default_tags
          ci_span.set_environment_runtime_tags

          ci_span.set_tags(tags)
          ci_span.set_tags(@environment_tags)
        end

        # PROPAGATING CONTEXT FROM TOP-LEVEL TO THE LOWER LEVELS
        def set_inherited_globals(tags)
          # this code achieves the same as @global_context.inheritable_session_tags.merge(tags)
          # but without allocating a new hash
          @global_context.inheritable_session_tags.each do |key, value|
            tags[key] = value unless tags.key?(key)
          end
        end

        def set_session_context(tags, test_session = nil)
          test_session ||= active_test_session
          tags[Ext::Test::TAG_TEST_SESSION_ID] = test_session.id.to_s if test_session
        end

        def set_module_context(tags, test_module = nil)
          test_module ||= active_test_module
          if test_module
            tags[Ext::Test::TAG_TEST_MODULE_ID] = test_module.id.to_s
            tags[Ext::Test::TAG_MODULE] = test_module.name
          end
        end

        def set_suite_context(tags, span: nil, name: nil)
          return if span.nil? && name.nil?

          test_suite = span || active_test_suite(name)

          if test_suite
            tags[Ext::Test::TAG_TEST_SUITE_ID] = test_suite.id.to_s
            tags[Ext::Test::TAG_SUITE] = test_suite.name
          else
            tags[Ext::Test::TAG_SUITE] = name
          end
        end

        # INTERACTIONS WITH TRACING
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

        # Sets trace's origin to ciapp-test because tracing requires so
        def set_trace_origin(trace)
          trace&.origin = Ext::Test::CONTEXT_ORIGIN
        end

        def build_tracing_span_options(service, type, other_options = {})
          other_options[:service] = service || @global_context.service
          other_options[:type] = type

          other_options
        end
      end
    end
  end
end
