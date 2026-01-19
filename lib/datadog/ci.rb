# frozen_string_literal: true

require_relative "ci/version"
require_relative "ci/utils/configuration"
require_relative "ci/utils/telemetry"
require_relative "ci/ext/app_types"
require_relative "ci/ext/telemetry"
require_relative "ci/configuration/supported_configurations"

require "datadog"
require "datadog/core"

module Datadog
  # Datadog Test Optimization public API.
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
      #   tags: { Datadog::CI::Ext::Test::TAG_FRAMEWORK => "my-test-framework" },
      #   total_tests_count: 100
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
      # @param [Integer] total_tests_count the total number of tests in the test session (optional, defaults to 0) - it is used to limit the number of new tests retried within session if early flake detection is enabled
      # @return [Datadog::CI::TestSession] the active, running {Datadog::CI::TestSession}.
      # @return [nil] if test suite level visibility is disabled or CI mode is disabled.
      def start_test_session(service: Utils::Configuration.fetch_service_name("test"), tags: {}, total_tests_count: 0)
        Utils::Telemetry.inc(
          Ext::Telemetry::METRIC_MANUAL_API_EVENTS,
          1,
          {Ext::Telemetry::TAG_EVENT_TYPE => Ext::Telemetry::EventType::SESSION}
        )
        test_visibility.start_test_session(service: service, tags: tags, estimated_total_tests_count: total_tests_count)
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
        test_visibility.active_test_session
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
        Utils::Telemetry.inc(
          Ext::Telemetry::METRIC_MANUAL_API_EVENTS,
          1,
          {Ext::Telemetry::TAG_EVENT_TYPE => Ext::Telemetry::EventType::MODULE}
        )

        test_visibility.start_test_module(test_module_name, service: service, tags: tags)
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
        test_visibility.active_test_module
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
        Utils::Telemetry.inc(
          Ext::Telemetry::METRIC_MANUAL_API_EVENTS,
          1,
          {Ext::Telemetry::TAG_EVENT_TYPE => Ext::Telemetry::EventType::SUITE}
        )

        test_visibility.start_test_suite(test_suite_name, service: service, tags: tags)
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
      # Most of the time, there is only one active test suite - except when using minitest with parallel test runner,
      # such as rails built-in test runner.
      #
      # When using RSpec or minitest without parallel test runner, there is only one active test suite, so you can use the following code to fetch it:
      #
      # ```
      # test_suite = Datadog::CI.active_test_suite
      # test_suite.finish
      # ```
      #
      # @param test_suite_name [String?] the name of the test suite to fetch. Optional. When not provided, it assumes that there is a single active test suite and returns it. If there are multiple active test suites and test_suite_name is not provided, it returns nil.
      #
      # @return [Datadog::CI::TestSuite] the active test suite
      # @return [nil] if no test suite with given name is active
      def active_test_suite(test_suite_name = nil)
        test_visibility.active_test_suite(test_suite_name)
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
        Utils::Telemetry.inc(
          Ext::Telemetry::METRIC_MANUAL_API_EVENTS,
          1,
          {Ext::Telemetry::TAG_EVENT_TYPE => Ext::Telemetry::EventType::TEST}
        )

        test_visibility.trace_test(test_name, test_suite_name, service: service, tags: tags, &block)
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
        Utils::Telemetry.inc(
          Ext::Telemetry::METRIC_MANUAL_API_EVENTS,
          1,
          {Ext::Telemetry::TAG_EVENT_TYPE => Ext::Telemetry::EventType::TEST}
        )
        test_visibility.trace_test(test_name, test_suite_name, service: service, tags: tags)
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
      # @return [nil] if Test Optimization is disabled
      # @raise [ReservedTypeError] if provided type is reserved for Datadog Test Optimization
      # @yield Optional block where newly created {Datadog::CI::Span} captures the execution.
      # @yieldparam [Datadog::CI::Span] ci_span the newly created and active [Datadog::CI::Span]
      # @yieldparam [nil] ci_span if Test Optimization is disabled
      def trace(span_name, type: "span", tags: {}, &block)
        if Ext::AppTypes::CI_SPAN_TYPES.include?(type)
          raise(
            ReservedTypeError,
            "Span type #{type} is reserved for Datadog Test Optimization. " \
              "Reserved types are: #{Ext::AppTypes::CI_SPAN_TYPES}"
          )
        end

        test_visibility.trace(span_name, type: type, tags: tags, &block)
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
      #   "Given I have 42 cucumbers",
      #   type: "step",
      #   tags: {}
      # )
      #
      # # somewhere else, access the active step span
      # step_span = Datadog::CI.active_span
      # step_span.finish()
      # ```
      #
      # @return [Datadog::CI::Span] the active span
      # @return [nil] if no span is active, or if the active span is not a custom span
      def active_span
        span = test_visibility.active_span
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
        test_visibility.active_test
      end

      private

      def components
        Datadog.send(:components)
      end

      def test_visibility
        components.test_visibility
      end

      def test_optimisation
        components.test_optimisation
      end

      def test_management
        components.test_management
      end

      def test_retries
        components.test_retries
      end
    end
  end

  # Monkey-patch DATADOG_ENV to use datadog-ci-rb envs
  # Only add datadog-ci-rb env vars if Datadog gem version is >= 2.27.0.
  DATADOG_ENV = if Gem::Version.new(::Datadog::VERSION::STRING) >= Gem::Version.new("2.27.0")
    ::Datadog::Core::Configuration::ConfigHelper.new(
      supported_configurations: Datadog::CI::Configuration::SUPPORTED_CONFIGURATION_NAMES + ::Datadog::Core::Configuration::SUPPORTED_CONFIGURATION_NAMES,
      aliases: Datadog::CI::Configuration::ALIASES.merge(::Datadog::Core::Configuration::ALIASES),
      alias_to_canonical: Datadog::CI::Configuration::ALIAS_TO_CANONICAL.merge(::Datadog::Core::Configuration::ALIAS_TO_CANONICAL)
    )
  elsif defined?(::Datadog::DATADOG_ENV)
    ::Datadog::DATADOG_ENV
  else
    ENV
  end
end

# Integrations

# Test frameworks
require_relative "ci/contrib/cucumber/integration"
require_relative "ci/contrib/minitest/integration"
require_relative "ci/contrib/rspec/integration"

# Test runners
require_relative "ci/contrib/knapsack/integration"
require_relative "ci/contrib/ciqueue/integration"
require_relative "ci/contrib/parallel_tests/integration"

# Additional test libraries (auto instrumented on test session start)
require_relative "ci/contrib/selenium/integration"
require_relative "ci/contrib/cuprite/integration"
require_relative "ci/contrib/simplecov/integration"
require_relative "ci/contrib/activesupport/integration"
require_relative "ci/contrib/lograge/integration"
require_relative "ci/contrib/semantic_logger/integration"

# Configuration extensions
require_relative "ci/configuration/extensions"
Datadog::CI::Configuration::Extensions.activate!
