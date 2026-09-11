# frozen_string_literal: true

require "set"

module Datadog
  module CI
    module TestTracing
      # Special test visibility component that does not record anything
      class NullComponent
        attr_reader :known_tests, :known_tests_enabled, :context_service_uri, :local_test_suites_mode

        def initialize
          @known_tests = Set.new
          @known_tests_enabled = false
          @context_service_uri = nil
          @local_test_suites_mode = true
        end

        def configure(_, _)
        end

        def start_test_session(
          service: nil, tags: {}, estimated_total_tests_count: 0, distributed: nil, local_test_suites_mode: true
        )
          skip_tracing
        end

        def start_test_module(test_module_name, service: nil, tags: {})
          skip_tracing
        end

        def start_test_suite(test_suite_name, service: nil, tags: {})
          skip_tracing
        end

        def trace_test(test_name, test_suite_name, service: nil, tags: {}, &block)
          skip_tracing(block)
        end

        def trace(span_name, type: "span", tags: {}, &block)
          skip_tracing(block)
        end

        def active_span
        end

        def active_test
        end

        def active_test_session
        end

        def active_test_module
        end

        def active_test_suite(test_suite_name)
        end

        def deactivate_test
        end

        def deactivate_test_session
        end

        def deactivate_test_module
        end

        def deactivate_test_suite(_test_suite_name)
        end

        def shutdown!
        end

        def itr_enabled?
          false
        end

        def logical_test_session_name
        end

        def client_process?
          false
        end

        def restore_state_from_datadog_test_runner
          false
        end

        private

        def skip_tracing(block = nil)
          block&.call(nil)
        end
      end
    end
  end
end
