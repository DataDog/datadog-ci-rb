# frozen_string_literal: true

require "json"

require_relative "span"

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

      # Finishes the current test.
      # @return [void]
      def finish
        super

        recorder.deactivate_test
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

      # Source file path of the test relative to git repository root.
      # @return [String] the source file path of the test
      # @return [nil] if the source file path is not found
      def source_file
        get_tag(Ext::Test::TAG_SOURCE_FILE)
      end

      # Sets the parameters for this test (e.g. Cucumber example or RSpec shared specs).
      # Parameters are needed to compute test fingerprint to distinguish between different tests having same names.
      #
      # @param [Hash] arguments the arguments that test accepts as key-value hash
      # @param [Hash] metadata optional metadata
      # @return [void]
      def set_parameters(arguments, metadata = {})
        return if arguments.nil?

        set_tag(
          Ext::Test::TAG_PARAMETERS,
          JSON.generate(
            {
              arguments: arguments,
              metadata: metadata
            }
          )
        )
      end
    end
  end
end
