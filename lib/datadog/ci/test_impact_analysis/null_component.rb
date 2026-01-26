# frozen_string_literal: true

require "set"

module Datadog
  module CI
    module TestImpactAnalysis
      # No-op implementation used when test impact analysis is disabled.
      class NullComponent
        attr_reader :enabled, :skippable_tests_fetch_error, :test_skipping_enabled,
          :code_coverage_enabled, :skippable_tests, :correlation_id

        def initialize
          @enabled = false
          @test_skipping_enabled = false
          @code_coverage_enabled = false
          @skippable_tests_fetch_error = nil
          @skippable_tests = Set.new
          @correlation_id = nil
        end

        def configure(_remote_configuration = nil, _test_session = nil)
        end

        def enabled?
          false
        end

        def skipping_tests?
          false
        end

        def code_coverage?
          false
        end

        def start_coverage
        end

        def stop_coverage
          nil
        end

        def on_test_context_started(_context_id)
        end

        def on_test_started(_test)
        end

        def on_test_finished(_test, _context)
          nil
        end

        def clear_context_coverage(_context_id)
        end

        def context_coverage_enabled?
          false
        end

        def mark_if_skippable(_test)
        end

        def skippable?(_datadog_test_id)
          false
        end

        def write_test_session_tags(_test_session, _skipped_tests_count)
        end

        def skippable_tests_count
          0
        end

        def shutdown!
        end
      end
    end
  end
end
