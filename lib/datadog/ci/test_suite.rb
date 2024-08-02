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
      def record_test_result(test_id, datadog_test_status)
        synchronize do
          @execution_stats_per_test[test_id] ||= Hash.new(0)
          @execution_stats_per_test[test_id][datadog_test_status] += 1
        end
      end

      private

      def set_status_from_stats!
        synchronize do
          # count how many tests passed, failed and skipped
          test_suite_stats = @execution_stats_per_test.each_with_object(Hash.new(0)) do |(_test_id, stats), acc|
            acc[derive_test_status_from_execution_stats(stats)] += 1
          end

          if test_suite_stats[Ext::Test::Status::FAIL] > 0
            failed!
          elsif test_suite_stats[Ext::Test::Status::PASS] == 0
            skipped!
          else
            passed!
          end
        end
      end

      def derive_test_status_from_execution_stats(test_execution_stats)
        # test is passed if it passed at least once
        if test_execution_stats[Ext::Test::Status::PASS] > 0
          Ext::Test::Status::PASS
        # if test was never passed, it is failed if it failed at least once
        elsif test_execution_stats[Ext::Test::Status::FAIL] > 0
          Ext::Test::Status::FAIL
        # otherwise it is skipped
        else
          Ext::Test::Status::SKIP
        end
      end
    end
  end
end
