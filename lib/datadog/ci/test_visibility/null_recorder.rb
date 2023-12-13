# frozen_string_literal: true

require_relative "recorder"

module Datadog
  module CI
    module TestVisibility
      # Special recorder that does not record anything
      class NullRecorder
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

        def trace(span_type, span_name, tags: {}, &block)
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

        def deactivate_test(test)
        end

        def deactivate_test_session
        end

        def deactivate_test_module
        end

        def deactivate_test_suite(test_suite_name)
        end

        private

        def skip_tracing(block = nil)
          if block
            block.call(null_span)
          else
            null_span
          end
        end

        def null_span
          @null_span ||= NullSpan.new
        end
      end
    end
  end
end
