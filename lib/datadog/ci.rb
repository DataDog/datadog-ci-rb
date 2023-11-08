# frozen_string_literal: true

require_relative "ci/version"

require "datadog/core"

module Datadog
  # Datadog CI visibility public API.
  #
  # @public_api
  module CI
    class << self
      # Return a {Datadog::CI::Test ci_test} that will trace a test called `test_name`.
      # Raises an error if a test is already active.
      #
      # You could trace your test using a <tt>do-block</tt> like:
      #
      # ```
      # Datadog::CI.trace_test(
      #   "test_add_two_numbers",
      #   service_name: "my-web-site-tests",
      #   operation_name: "test",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # ) do |ci_test|
      #   result = run_test
      #
      #   if result.ok?
      #     ci_test.passed!
      #   else
      #     ci_test.failed!(exception: result.exception)
      #   end
      # end
      # ```
      #
      # The {#trace_test} method can also be used without a block in this way:
      # ```
      # ci_test = Datadog::CI.trace_test(
      #   "test_add_two_numbers',
      #   service: "my-web-site-tests",
      #   operation_name: "test",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      # run_test
      # ci_test.finish
      # ```
      #
      # Remember that in this case, calling {Datadog::CI::Test#finish} is mandatory.
      #
      # @param [String] test_name {Datadog::CI::Test} name (example: "test_add_two_numbers").
      # @param [String] operation_name defines label for a test span in trace view ("test" if it's missing)
      # @param [String] service_name the service name for this test
      # @param [Hash<String,String>] tags extra tags which should be added to the test.
      # @return [Object] If a block is provided, returns the result of the block execution.
      # @return [Datadog::CI::Test] If no block is provided, returns the active,
      #         unfinished {Datadog::CI::Test}.
      # @yield Optional block where new newly created {Datadog::CI::Test} captures the execution.
      # @yieldparam [Datadog::CI::Test] ci_test the newly created and active [Datadog::CI::Test]
      #
      # @public_api
      def trace_test(test_name, service_name: nil, operation_name: "test", tags: {}, &block)
        recorder.trace_test(test_name, service_name: service_name, operation_name: operation_name, tags: tags, &block)
      end

      # Same as {#trace_test} but it does not accept a block.
      # Raises an error if a test is already active.
      #
      # Usage:
      #
      # ```
      # ci_test = Datadog::CI.start_test(
      #   "test_add_two_numbers',
      #   service: "my-web-site-tests",
      #   operation_name: "test",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      # run_test
      # ci_test.finish
      # ```
      #
      # @param [String] test_name {Datadog::CI::Test} name (example: "test_add_two_numbers").
      # @param [String] operation_name the resource this span refers, or `test` if it's missing
      # @param [String] service_name the service name for this span.
      # @param [Hash<String,String>] tags extra tags which should be added to the test.
      # @return [Datadog::CI::Test] Returns the active, unfinished {Datadog::CI::Test}.
      #
      # @public_api
      def start_test(test_name, service_name: nil, operation_name: "test", tags: {})
        recorder.trace_test(test_name, service_name: service_name, operation_name: operation_name, tags: tags)
      end

      # Trace any custom span inside a test. For example, you could trace:
      # - cucumber step
      # - database query
      # - any custom operation you want to see in your trace view
      #
      # You can use thi method with a <tt>do-block</tt> like:
      #
      # ```
      # Datadog::CI.trace(
      #   "step",
      #   "Given I have 42 cucumbers",
      #   tags: {}
      # ) do
      #   run_operation
      # end
      # ```
      #
      # The {#trace} method can also be used without a block in this way:
      # ```
      # ci_span = Datadog::CI.trace(
      #   "step",
      #   "Given I have 42 cucumbers",
      #   tags: {}
      # )
      # run_test
      # ci_span.finish
      # ```
      # Remember that in this case, calling {Datadog::CI::Span#finish} is mandatory.
      #
      # @param [String] span_type custom, user-defined span type (for example "step" or "query").
      # @param [String] span_name the resource this span refers, or `test` if it's missing
      # @param [Hash<String,String>] tags extra tags which should be added to the span.
      # @return [Object] If a block is provided, returns the result of the block execution.
      # @return [Datadog::CI::Span] If no block is provided, returns the active,
      #         unfinished {Datadog::CI::Span}.
      # @yield Optional block where new newly created {Datadog::CI::Span} captures the execution.
      # @yieldparam [Datadog::CI::Span] ci_span the newly created and active [Datadog::CI::Span]
      #
      # @public_api
      def trace(span_type, span_name, tags: {}, &block)
        recorder.trace(span_type, span_name, tags: tags, &block)
      end

      # The active, unfinished custom span if it matches given type.
      # If no span is active, or if the active span is not a custom span with given type, returns nil.
      #
      # The active span belongs to an {.active_test}.
      #
      # Usage:
      #
      # ```
      # # start span
      # Datadog::CI.trace(
      #   "step",
      #   "Given I have 42 cucumbers",
      #   tags: {}
      # )
      #
      # # somewhere else, access the active "step" span
      # step_span = Datadog::CI.active_span("step")
      # step_span.finish()
      # ```
      #
      # @param [String] span_type type of the span to retrieve (for example "step" or "query") that was provided to {.trace}
      # @return [Datadog::CI::Span] the active span
      # @return [nil] if no span is active, or if the active span is not a custom span with given type
      def active_span(span_type)
        span = recorder.active_span
        span if span && span.span_type == span_type
      end

      # The active, unfinished test span.
      #
      # Usage:
      #
      # ```
      # # start a test
      # Datadog::CI.start_test(
      #   "test_add_two_numbers',
      #   service: "my-web-site-tests",
      #   operation_name: "test",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      #
      # # somewhere else, access the active test
      # test_span = Datadog::CI.active_test
      # test_span.passed!
      # test_span.finish
      # ```
      #
      # @return [Datadog::CI::Test] the active test
      # @return [nil] if no test is active
      def active_test
        recorder.active_test
      end

      # Internal only, to finish a test use Datadog::CI::Test#finish
      def deactivate_test(test)
        recorder.deactivate_test(test)
      end

      private

      def components
        Datadog.send(:components)
      end

      def recorder
        components.ci_recorder
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
