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

        # counts how many times every test in this suite was executed with each status:
        #   { "MySuite.mytest.a:1" => { "pass" => 3, "fail" => 2 } }
        @execution_stats_per_test = {}

        # tracks final status for each test (the status that is reported after all retries):
        #   { "MySuite.mytest.a:1" => "pass" }
        @final_statuses_per_test = {}
      end

      # Finishes this test suite.
      # @return [void]
      def finish
        synchronize do
          # we try to derive test suite status from execution stats if no status was set explicitly
          set_status_from_stats! if undefined?

          test_tracing.deactivate_test_suite(name)

          super
        end
      end

      # @internal
      def record_test_result(test_id, datadog_test_status)
        synchronize do
          @execution_stats_per_test[test_id] ||= Hash.new(0)
          @execution_stats_per_test[test_id][datadog_test_status] += 1
        end
      end

      # @internal
      def record_test_final_status(test_id, final_status)
        synchronize do
          @final_statuses_per_test[test_id] = final_status
        end
      end

      # @internal
      def any_passed?
        synchronize do
          @execution_stats_per_test.any? do |_, stats|
            stats[Ext::Test::Status::PASS] > 0
          end
        end
      end

      # @internal
      def any_test_retry_passed?(test_id)
        synchronize do
          stats = @execution_stats_per_test[test_id]
          stats && stats[Ext::Test::Status::PASS] > 0
        end
      end

      # @internal
      def all_executions_failed?(test_id)
        synchronize do
          stats = @execution_stats_per_test[test_id]
          stats && stats[Ext::Test::Status::FAIL] > 0 && stats[Ext::Test::Status::PASS] == 0
        end
      end

      # @internal
      def all_executions_passed?(test_id)
        synchronize do
          stats = @execution_stats_per_test[test_id]
          stats && stats[Ext::Test::Status::PASS] > 0 && stats[Ext::Test::Status::FAIL] == 0
        end
      end

      # @internal
      def test_executed?(test_id)
        synchronize do
          @execution_stats_per_test.key?(test_id)
        end
      end

      # @internal
      def set_expected_tests!(expected_tests)
        synchronize do
          return if @expected_tests_set

          @expected_tests_set = Set.new(expected_tests)
        end
      end

      # @internal
      def expected_test_done!(test_name)
        synchronize do
          @expected_tests_set.delete(test_name)

          finish if @expected_tests_set.empty?
        end
      end

      private

      def set_status_from_stats!
        synchronize do
          # count how many tests have each final status
          test_suite_stats = @final_statuses_per_test.each_with_object(Hash.new(0)) do |(_test_id, final_status), acc|
            acc[final_status] += 1
          end

          # test suite is considered failed if at least one test failed
          if test_suite_stats[Ext::Test::Status::FAIL] > 0
            failed!
          # if there are no failures and no passes, it is skipped
          elsif test_suite_stats[Ext::Test::Status::PASS] == 0
            skipped!
          # otherwise we consider it passed
          else
            passed!
          end
        end
      end
    end
  end
end
