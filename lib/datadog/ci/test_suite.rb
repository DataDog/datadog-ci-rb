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

        @custom_impacted_files = []

        # counts how many times every test in this suite was executed with each status:
        #   { "MySuite.mytest.a:1" => { "pass" => 3, "fail" => 2 } }
        @execution_stats_per_test = {}

        # tracks final status for each test (the status that is reported after all retries):
        #   { "MySuite.mytest.a:1" => "pass" }
        @final_statuses_per_test = {}
      end

      # Adds files that Test Impact Analysis should consider capable of
      # impacting every test in this suite.
      #
      # In test-level skipping mode, custom impacted files must be added before
      # the first test in this suite starts. In suite-level skipping mode, they
      # may be added until the suite finishes.
      #
      # This is useful for files shared by every test that Datadog's native
      # Ruby coverage cannot observe, such as JavaScript test setup. Calls are
      # incremental: every call adds files for the remainder of the suite.
      #
      # Paths must resolve inside the Git repository. Relative paths must be
      # relative to the repository root. Absolute paths are also accepted.
      #
      # If paths are relative to the current working directory, convert them to
      # absolute paths with +File.expand_path+ before calling this method.
      # Submitted paths must be lexically normalized without redundant +.+ or
      # +..+ components. Resolution does not access the filesystem. Paths
      # outside the repository are ignored when the coverage event is
      # serialized.
      #
      # @example Register JavaScript setup shared by an RSpec suite
      #   before(:context) do
      #     Datadog::CI.active_test_suite&.add_impacted_files(
      #       ["app/frontend/test_setup.js"]
      #     )
      #   end
      #
      # @raise [RuntimeError] if test-level skipping is active and a test in
      #   this suite has already started
      # @param [Array<String>] file_paths custom paths that can impact this suite
      # @raise [ArgumentError] if file_paths is not an Array
      # @return [void]
      def add_impacted_files(file_paths)
        raise ArgumentError, "file_paths must be an Array" unless file_paths.is_a?(Array)

        synchronize do
          ensure_custom_impacted_files_mutable!
          @custom_impacted_files.concat(file_paths)
        end
        nil
      end

      # Locks suite-level custom impacted files against further changes and
      # returns them to Test Impact Analysis.
      #
      # @internal
      # @return [Array<String>]
      def lock_custom_impacted_files
        synchronize do
          unless @custom_impacted_files.frozen?
            @custom_impacted_files = @custom_impacted_files.uniq.freeze
          end
          @custom_impacted_files
        end
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

      # @internal
      def datadog_skip_reason
        get_tag(Ext::Test::TAG_SKIP_REASON)
      end

      # @internal
      def should_skip?
        skipped_by_test_impact_analysis?
      end

      # @internal
      def skipped_by_test_impact_analysis?
        get_tag(Ext::Test::TAG_ITR_SKIPPED_BY_ITR) == "true"
      end

      # @internal
      def itr_unskippable?
        get_tag(Ext::Test::TAG_ITR_UNSKIPPABLE) == "true"
      end

      private

      def ensure_custom_impacted_files_mutable!
        return unless @custom_impacted_files.frozen?

        raise(
          "Custom impacted files must be added to a test suite before the first test in the suite starts"
        )
      end

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
