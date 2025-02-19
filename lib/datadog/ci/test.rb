# frozen_string_literal: true

require "json"

require_relative "span"
require_relative "test_optimisation/telemetry"
require_relative "utils/test_run"

module Datadog
  module CI
    # Represents a single part of a test run.
    #
    # @public_api
    class Test < Span
      # @return [String] the name of the test.
      def name
        get_tag(Ext::Test::TAG_NAME)
      end

      # @return [String] the test id according to Datadog's test impact analysis.
      def datadog_test_id
        @datadog_test_id ||= Utils::TestRun.datadog_test_id(name, test_suite_name, parameters)
      end

      # Finishes the current test.
      # @return [void]
      def finish
        test_visibility.deactivate_test

        super
      end

      # Running test suite that this test is part of (if any).
      # @return [Datadog::CI::TestSuite] the test suite this test belongs to
      # @return [nil] if the test suite is not found
      def test_suite
        suite_name = test_suite_name
        CI.active_test_suite(suite_name) if suite_name
      end

      # Span id of the running test suite this test belongs to.
      # @return [String] the span id of the test suite.
      def test_suite_id
        get_tag(Ext::Test::TAG_TEST_SUITE_ID)
      end

      # Name of the running test suite this test belongs to.
      # @return [String] the name of the test suite.
      def test_suite_name
        get_tag(Ext::Test::TAG_SUITE)
      end

      # Span id of the running test module this test belongs to.
      # @return [String] the span id of the test module.
      def test_module_id
        get_tag(Ext::Test::TAG_TEST_MODULE_ID)
      end

      # Span id of the running test session this test belongs to.
      # @return [String] the span id of the test session.
      def test_session_id
        get_tag(Ext::Test::TAG_TEST_SESSION_ID)
      end

      # Returns "true" if test span represents a retry.
      # @return [Boolean] true if this test is a retry, false otherwise.
      def is_retry?
        get_tag(Ext::Test::TAG_IS_RETRY) == "true"
      end

      # Returns "true" if this span represents a test that wasn't known to Datadog before.
      # @return [Boolean] true if this test is a new one, false otherwise.
      def is_new?
        get_tag(Ext::Test::TAG_IS_NEW) == "true"
      end

      # Returns "true" if this test is quarantined by Datadog test management.
      # @return [Boolean] true if this test is quarantined, false otherwise.
      def quarantined?
        get_tag(Ext::Test::TAG_IS_QUARANTINED) == "true"
      end

      # Returns "true" if this test is disabled by Datadog test management.
      # @return [Boolean] true if this test is disabled, false otherwise.
      def disabled?
        get_tag(Ext::Test::TAG_IS_TEST_DISABLED) == "true"
      end

      # Marks this test as unskippable by the Test Impact Analysis.
      # This must be done before the test execution starts.
      #
      # Examples of tests that should be unskippable:
      # - tests that read files from disk
      # - tests that make network requests
      # - tests that call external processes
      # - tests that use forking
      #
      # @return [void]
      def itr_unskippable!
        TestOptimisation::Telemetry.itr_unskippable
        set_tag(Ext::Test::TAG_ITR_UNSKIPPABLE, "true")

        if skipped_by_test_impact_analysis?
          clear_tag(Ext::Test::TAG_ITR_SKIPPED_BY_ITR)

          TestOptimisation::Telemetry.itr_forced_run
          set_tag(Ext::Test::TAG_ITR_FORCED_RUN, "true")
        end
      end

      # Sets the status of the span to "pass".
      # @return [void]
      def passed!
        super

        record_test_result(Ext::Test::Status::PASS)
      end

      # Sets the status of the span to "fail".
      # @param [Exception] exception the exception that caused the test to fail.
      # @return [void]
      def failed!(exception: nil)
        super

        # if we should ignore failures, we consider this test to be passed
        if should_ignore_failures?
          record_test_result(Ext::Test::Status::PASS)
        else
          record_test_result(Ext::Test::Status::FAIL)
        end
      end

      # Sets the status of the span to "skip".
      # @param [Exception] exception the exception that caused the test to fail.
      # @param [String] reason the reason why the test was skipped.
      # @return [void]
      def skipped!(exception: nil, reason: nil)
        super

        record_test_result(Ext::Test::Status::SKIP)
      end

      # Sets the parameters for this test (e.g. Cucumber example or RSpec specs).
      # Parameters are needed to compute test fingerprint to distinguish between different tests having same names.
      #
      # @param [Hash] arguments the arguments that test accepts as key-value hash
      # @param [Hash] metadata optional metadata
      # @return [void]
      def set_parameters(arguments, metadata = {})
        return if arguments.nil?

        set_tag(Ext::Test::TAG_PARAMETERS, Utils::TestRun.test_parameters(arguments: arguments, metadata: metadata))
      end

      # Gets the parameters for this test (e.g. Cucumber example or RSpec specs) as a serialized JSON.
      #
      # @return [String] the serialized JSON of the parameters
      # @return [nil] if this test does not have parameters
      def parameters
        get_tag(Ext::Test::TAG_PARAMETERS)
      end

      # @internal
      def any_retry_passed?
        !!test_suite&.any_test_retry_passed?(datadog_test_id)
      end

      # @internal
      def datadog_skip_reason
        if skipped_by_test_impact_analysis?
          Ext::Test::SkipReason::TEST_IMPACT_ANALYSIS
        elsif disabled? || quarantined?
          Ext::Test::SkipReason::TEST_MANAGEMENT_DISABLED
        end
      end

      # @internal
      def should_skip?
        skipped_by_test_impact_analysis? || disabled?
      end

      # @internal
      def should_ignore_failures?
        quarantined? || disabled? || any_retry_passed?
      end

      # @internal
      def skipped_by_test_impact_analysis?
        get_tag(Ext::Test::TAG_ITR_SKIPPED_BY_ITR) == "true"
      end

      private

      def record_test_result(datadog_status)
        # if this test was already executed in this test suite, mark it as retried
        if test_suite&.test_executed?(datadog_test_id)
          set_tag(Ext::Test::TAG_IS_RETRY, "true")
        end

        test_suite&.record_test_result(datadog_test_id, datadog_status)
      end
    end
  end
end
