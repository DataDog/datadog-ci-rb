# frozen_string_literal: true

require_relative "driver/no_retry"
require_relative "driver/retry_failed"
require_relative "driver/retry_flake_detection"

require_relative "strategy/no_retry"
require_relative "strategy/retry_failed"
require_relative "strategy/retry_flake_detection"
require_relative "strategy/retry_flaky_fixed"

require_relative "../ext/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module TestRetries
      # Encapsulates the logic to enable test retries, including:
      # - retrying failed tests - improve success rate of CI pipelines
      # - retrying new tests - detect flaky tests as early as possible to prevent them from being merged
      class Component
        FIBER_LOCAL_CURRENT_RETRY_DRIVER_KEY = :__dd_current_retry_driver

        def initialize(
          retry_failed_tests_enabled:,
          retry_failed_tests_max_attempts:,
          retry_failed_tests_total_limit:,
          retry_new_tests_enabled:,
          retry_flaky_fixed_tests_enabled:,
          retry_flaky_fixed_tests_max_attempts:
        )
          no_retries_strategy = Strategy::NoRetry.new

          retry_failed_strategy = Strategy::RetryFailed.new(
            enabled: retry_failed_tests_enabled,
            max_attempts: retry_failed_tests_max_attempts,
            total_limit: retry_failed_tests_total_limit
          )

          retry_flake_detection_strategy = Strategy::RetryFlakeDetection.new(
            enabled: retry_new_tests_enabled
          )

          retry_flaky_fixed_strategy = Strategy::RetryFlakyFixed.new(
            enabled: retry_flaky_fixed_tests_enabled,
            max_attempts: retry_flaky_fixed_tests_max_attempts
          )

          # order is important, we apply the first matching strategy
          @retry_strategies = [
            retry_flaky_fixed_strategy,
            retry_flake_detection_strategy,
            retry_failed_strategy,
            no_retries_strategy
          ]
          @mutex = Mutex.new
        end

        def configure(library_settings, test_session)
          # let all strategies configure themselves
          @retry_strategies.each do |strategy|
            strategy.configure(library_settings, test_session)
          end
        end

        def with_retries(&block)
          reset_retries!

          loop do
            yield

            break unless should_retry?
          end
        ensure
          reset_retries!
        end

        def build_driver(test_span)
          @mutex.synchronize do
            # find the first strategy that covers the test span and let it build the driver
            strategy = @retry_strategies.find { |strategy| strategy.covers?(test_span) }

            raise "No retry strategy found for test span: #{test_span.name}" if strategy.nil?

            strategy.build_driver(test_span)
          end
        end

        def record_test_started(test_span)
          # mark test as retry in the beginning
          # if this is a first execution, the current_retry_driver is nil and this is noop
          current_retry_driver&.mark_as_retry(test_span)
        end

        def record_test_finished(test_span)
          if current_retry_driver.nil?
            # We always run test at least once and after the first pass create a correct retry driver
            self.current_retry_driver = build_driver(test_span)
          else
            # After each retry we let the driver to record the result.
            # Then the driver will decide if we should retry again.
            current_retry_driver&.record_retry(test_span)

            # We know that the test was already retried at least once so if we should not retry anymore, then this
            # is the last retry.
            tag_last_retry(test_span) unless should_retry?
          end

          # Some retry strategies such as Early Flake Detection change the number of retries based on
          # how long the test was.
          current_retry_driver&.record_duration(test_span.peek_duration)

          # We need to set the final status of the test (what will be reported to the test framework) on the last execution
          # no matter if test was retried or not
          #
          # If we should not retry at this point, it means that this execution is the last one (it might the only one as well).
          test_span.record_final_status unless should_retry?
        end

        # this API is targeted on Cucumber instrumentation or any other that cannot leverage #with_retries method
        def reset_retries!
          self.current_retry_driver = nil
        end

        def tag_last_retry(test_span)
          test_span&.set_tag(Ext::Test::TAG_HAS_FAILED_ALL_RETRIES, "true") if test_span&.all_executions_failed?

          # if we are attempting to fix the test and all retries passed, we indicate that the fix might have worked
          # otherwise we send "false" to show that it didn't work
          test_span&.set_tag(Ext::Test::TAG_ATTEMPT_TO_FIX_PASSED, test_span&.all_executions_passed?.to_s) if test_span&.attempt_to_fix?
        end

        def should_retry?
          !!current_retry_driver&.should_retry?
        end

        private

        def current_retry_driver
          Thread.current[FIBER_LOCAL_CURRENT_RETRY_DRIVER_KEY]
        end

        def current_retry_driver=(driver)
          Thread.current[FIBER_LOCAL_CURRENT_RETRY_DRIVER_KEY] = driver
        end
      end
    end
  end
end
