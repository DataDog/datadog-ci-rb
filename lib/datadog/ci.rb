# frozen_string_literal: true

require_relative "ci/version"
require_relative "ci/utils/configuration"
require_relative "ci/ext/app_types"

require "datadog/core"

module Datadog
  # Datadog CI visibility public API.
  #
  # @public_api
  module CI
    class ReservedTypeError < StandardError; end

    class << self
      # Starts a {Datadog::CI::TestSession ci_test_session} that represents the whole test session run.
      #
      # Read Datadog documentation on test sessions
      # [here](https://docs.datadoghq.com/continuous_integration/explorer/?tab=testruns#sessions).
      #
      # Returns the existing test session if one is already active. There is at most a single test session per process.
      #
      # The {.start_test_session} method is used to mark the start of the test session:
      # ```
      # Datadog::CI.start_test_session(
      #   service: "my-web-site-tests",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      #
      # # Somewhere else after test run has ended
      # Datadog::CI.active_test_session.finish
      # ```
      #
      # Remember that calling {Datadog::CI::TestSession#finish} is mandatory.
      #
      # @param [String] service the service name for this session (optional, defaults to DD_SERVICE or repository name)
      # @param [Hash<String,String>] tags extra tags which should be added to the test session.
      # @return [Datadog::CI::TestSession] the active, running {Datadog::CI::TestSession}.
      # @return [nil] if test suite level visibility is disabled or CI mode is disabled.
      def start_test_session(service: Utils::Configuration.fetch_service_name("test"), tags: {})
        recorder.start_test_session(service: service, tags: tags)
      end

      # The active, unfinished test session.
      #
      # Usage:
      #
      # ```
      # # start a test session
      # Datadog::CI.start_test_session(
      #   service: "my-web-site-tests",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      #
      # # somewhere else, access the session
      # test_session = Datadog::CI.active_test_session
      # test_session.finish
      # ```
      #
      # @return [Datadog::CI::TestSession] the active test session
      # @return [nil] if no test session is active
      def active_test_session
        recorder.active_test_session
      end

      # Starts a {Datadog::CI::TestModule ci_test_module} that represents a single test module (for most Ruby test frameworks
      # module will correspond 1-1 to the test session).
      #
      # Read Datadog documentation on test modules
      # [here](https://docs.datadoghq.com/continuous_integration/explorer/?tab=testruns#module).
      #
      # Returns the existing test session if one is already active. There is at most a single test module per process
      # active at any given time.
      #
      # The {.start_test_module} method is used to mark the start of the test session:
      # ```
      # Datadog::CI.start_test_module(
      #   "my-module",
      #   service: "my-web-site-tests",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      #
      # # Somewhere else after the module has ended
      # Datadog::CI.active_test_module.finish
      # ```
      #
      # Remember that calling {Datadog::CI::TestModule#finish} is mandatory.
      #
      # @param [String] test_module_name the name for this module
      # @param [String] service the service name for this session (optional, inherited from test session if not provided)
      # @param [Hash<String,String>] tags extra tags which should be added to the test module (optional, some tags are inherited from test session).
      # @return [Datadog::CI::TestModule] the active, running {Datadog::CI::TestModule}.
      # @return [nil] if test suite level visibility is disabled or CI mode is disabled.
      def start_test_module(test_module_name, service: nil, tags: {})
        recorder.start_test_module(test_module_name, service: service, tags: tags)
      end

      # The active, unfinished test module.
      #
      # Usage:
      #
      # ```
      # # start a test module
      # Datadog::CI.start_test_module(
      #   "my-module",
      #   service: "my-web-site-tests",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      #
      # # somewhere else, access the current module
      # test_module = Datadog::CI.active_test_module
      # test_module.finish
      # ```
      #
      # @return [Datadog::CI::TestModule] the active test module
      # @return [nil] if no test module is active
      def active_test_module
        recorder.active_test_module
      end

      # Starts a {Datadog::CI::TestSuite ci_test_suite} that represents a single test suite.
      # If a test suite with given name is running, returns the existing test suite.
      #
      # Read Datadog documentation on test suites
      # [here](https://docs.datadoghq.com/continuous_integration/explorer/?tab=testruns#module).
      #
      # The {.start_test_suite} method is used to mark the start of a test suite:
      # ```
      # Datadog::CI.start_test_suite(
      #   "calculator_tests",
      #   service: "my-web-site-tests",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      #
      # # Somewhere else after the suite has ended
      # Datadog::CI.active_test_suite("calculator_tests").finish
      # ```
      #
      # Remember that calling {Datadog::CI::TestSuite#finish} is mandatory.
      #
      # @param [String] test_suite_name the name of the test suite
      # @param [String] service the service name for this test suite (optional, inherited from test session if not provided)
      # @param [Hash<String,String>] tags extra tags which should be added to the test module (optional, some tags are inherited from test session)
      # @return [Datadog::CI::TestSuite] the active, running {Datadog::CI::TestSuite}.
      # @return [nil] if test suite level visibility is disabled or CI mode is disabled.
      def start_test_suite(test_suite_name, service: nil, tags: {})
        recorder.start_test_suite(test_suite_name, service: service, tags: tags)
      end

      # The active, unfinished test suite.
      #
      # Usage:
      #
      # ```
      # # start a test suite
      # Datadog::CI.start_test_suite(
      #   "calculator_tests",
      #   service: "my-web-site-tests",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      #
      # # Somewhere else after the suite has ended
      # test_suite = Datadog::CI.active_test_suite("calculator_tests")
      # test_suite.finish
      # ```
      #
      # @return [Datadog::CI::TestSuite] the active test suite
      # @return [nil] if no test suite with given name is active
      def active_test_suite(test_suite_name)
        recorder.active_test_suite(test_suite_name)
      end

      # Return a {Datadog::CI::Test ci_test} that will trace a test called `test_name`.
      # Raises an error if a test is already active.
      # If there is an active test session, the new test will be connected to the session.
      # The test will inherit service name and tags from the running test session if not provided
      # in parameters.
      #
      # You could trace your test using a <tt>do-block</tt> like:
      #
      # ```
      # Datadog::CI.trace_test(
      #   "test_add_two_numbers",
      #   "calculator_tests",
      #   service: "my-web-site-tests",
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
      # The {.trace_test} method can also be used without a block in this way:
      # ```
      # ci_test = Datadog::CI.trace_test(
      #   "test_add_two_numbers",
      #   "calculator_tests",
      #   service: "my-web-site-tests",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      # # ... run test here ...
      # ci_test.finish
      # ```
      #
      # Remember that in this case, calling {Datadog::CI::Test#finish} is mandatory.
      #
      # @param [String] test_name {Datadog::CI::Test} name (example: "test_add_two_numbers").
      # @param [String] test_suite_name name of test suite this test belongs to (example: "CalculatorTest").
      # @param [String] service the service name for this test (optional, inherited from test session if not provided)
      # @param [Hash<String,String>] tags extra tags which should be added to the test.
      # @return [Object] If a block is provided, returns the result of the block execution.
      # @return [Datadog::CI::Test] If no block is provided, returns the active,
      #         unfinished {Datadog::CI::Test}.
      # @return [nil] if no block is provided and CI mode is disabled.
      # @yield Optional block where newly created {Datadog::CI::Test} captures the execution.
      # @yieldparam [Datadog::CI::Test] ci_test the newly created and active [Datadog::CI::Test]
      # @yieldparam [nil] if CI mode is disabled
      def trace_test(test_name, test_suite_name, service: nil, tags: {}, &block)
        recorder.trace_test(test_name, test_suite_name, service: service, tags: tags, &block)
      end

      # Same as {.trace_test} but it does not accept a block.
      # Raises an error if a test is already active.
      #
      # Usage:
      #
      # ```
      # ci_test = Datadog::CI.start_test(
      #   "test_add_two_numbers",
      #   "calculator_tests",
      #   service: "my-web-site-tests",
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" }
      # )
      # # ... run test here ...
      # ci_test.finish
      # ```
      #
      # @param [String] test_name {Datadog::CI::Test} name (example: "test_add_two_numbers").
      # @param [String] test_suite_name name of test suite this test belongs to (example: "CalculatorTest").
      # @param [String] service the service name for this span (optional, inherited from test session if not provided)
      # @param [Hash<String,String>] tags extra tags which should be added to the test.
      # @return [Datadog::CI::Test] the active, unfinished {Datadog::CI::Test}.
      # @return [nil] if CI mode is disabled.
      def start_test(test_name, test_suite_name, service: nil, tags: {})
        recorder.trace_test(test_name, test_suite_name, service: service, tags: tags)
      end

      # Trace any custom span inside a test. For example, you could trace:
      # - cucumber step
      # - database query
      # - any custom operation you want to see in your trace view
      #
      # You can use this method with a <tt>do-block</tt> like:
      #
      # ```
      # Datadog::CI.trace(
      #   "Given I have 42 cucumbers",
      #   type: "step",
      #   tags: {}
      # ) do
      #   run_operation
      # end
      # ```
      #
      # The {.trace} method can also be used without a block in this way:
      # ```
      # ci_span = Datadog::CI.trace(
      #   "Given I have 42 cucumbers",
      #   type: "step",
      #   tags: {}
      # )
      # # ... run test here ...
      # ci_span.finish
      # ```
      # Remember that in this case, calling {Datadog::CI::Span#finish} is mandatory.
      #
      # @param [String] span_name the resource this span refers, or `test` if it's missing
      # @param [String] type custom, user-defined span type (for example "step" or "query").
      # @param [Hash<String,String>] tags extra tags which should be added to the span.
      # @return [Object] If a block is provided, returns the result of the block execution.
      # @return [Datadog::CI::Span] If no block is provided, returns the active,
      #         unfinished {Datadog::CI::Span}.
      # @return [nil] if CI visibility is disabled
      # @raise [ReservedTypeError] if provided type is reserved for Datadog CI visibility
      # @yield Optional block where newly created {Datadog::CI::Span} captures the execution.
      # @yieldparam [Datadog::CI::Span] ci_span the newly created and active [Datadog::CI::Span]
      # @yieldparam [nil] ci_span if CI visibility is disabled
      def trace(span_name, type: "span", tags: {}, &block)
        if Ext::AppTypes::CI_SPAN_TYPES.include?(type)
          raise(
            ReservedTypeError,
            "Span type #{type} is reserved for Datadog CI visibility. " \
              "Reserved types are: #{Ext::AppTypes::CI_SPAN_TYPES}"
          )
        end

        recorder.trace(span_name, type: type, tags: tags, &block)
      end

      # The active, unfinished custom (i.e. not test/suite/module/session) span.
      # If no span is active, or if the active span is not a custom span, returns nil.
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
      # @return [Datadog::CI::Span] the active span
      # @return [nil] if no span is active, or if the active span is not a custom span
      def active_span
        span = recorder.active_span
        span if span && !Ext::AppTypes::CI_SPAN_TYPES.include?(span.type)
      end

      # The active, unfinished test span.
      #
      # Usage:
      #
      # ```
      # # start a test
      # Datadog::CI.start_test(
      #   "test_add_two_numbers",
      #   "calculator_tests",
      #   service: "my-web-site-tests",
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

# Configuration extensions
require_relative "ci/configuration/extensions"
Datadog::CI::Configuration::Extensions.activate!
