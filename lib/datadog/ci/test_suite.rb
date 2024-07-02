# frozen_string_literal: true

require_relative "concurrent_span"

module Datadog
  module CI
    # Represents a single test suite.
    #
    # Read here on what test suite means:
    # https://docs.datadoghq.com/continuous_integration/explorer/?tab=testruns#suite
    #
    # This object can be shared between multiple threads.
    #
    # @public_api
    class TestSuite < ConcurrentSpan
      def initialize(tracer_span)
        super

        @test_suite_stats = Hash.new(0)
      end

      # Finishes this test suite.
      # @return [void]
      def finish
        synchronize do
          # we try to derive test suite status from execution stats if no status was set explicitly
          set_status_from_stats! if undefined?

          test_visibility.deactivate_test_suite(name)

          super
        end
      end

      # @internal
      def record_test_result(datadog_test_status)
        synchronize do
          @test_suite_stats[datadog_test_status] += 1
        end
      end

      # @internal
      def passed_tests_count
        synchronize do
          @test_suite_stats[Ext::Test::Status::PASS]
        end
      end

      # @internal
      def skipped_tests_count
        synchronize do
          @test_suite_stats[Ext::Test::Status::SKIP]
        end
      end

      # @internal
      def failed_tests_count
        synchronize do
          @test_suite_stats[Ext::Test::Status::FAIL]
        end
      end

      private

      def set_status_from_stats!
        if failed_tests_count > 0
          failed!
        elsif passed_tests_count == 0
          skipped!
        else
          passed!
        end
      end
    end
  end
end
