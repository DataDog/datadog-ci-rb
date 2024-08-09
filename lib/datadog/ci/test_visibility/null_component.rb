# frozen_string_literal: true

module Datadog
  module CI
    module TestVisibility
      # Special test visibility component that does not record anything
      class NullComponent
        def start_test_session(service: nil, tags: {})
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

        def shutdown!
        end

        def itr_enabled?
          false
        end

        def set_test_finished_callback(_)
        end

        def remove_test_finished_callback
        end

        private

        def skip_tracing(block = nil)
          block&.call(nil)
        end
      end
    end
  end
end
