# frozen_string_literal: true

require_relative "driver/no_retry"
require_relative "driver/retry_failed"
require_relative "driver/retry_new"

require_relative "strategy/no_retry"
require_relative "strategy/retry_failed"
require_relative "strategy/retry_new"

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
          unique_tests_client:
        )
          no_retries_strategy = Strategy::NoRetry.new

          retry_failed_strategy = Strategy::RetryFailed.new(
            enabled: retry_failed_tests_enabled,
            max_attempts: retry_failed_tests_max_attempts,
            total_limit: retry_failed_tests_total_limit
          )

          retry_new_strategy = Strategy::RetryNew.new(
            enabled: retry_new_tests_enabled,
            unique_tests_client: unique_tests_client
          )

          # order is important, we should try to retry new tests first
          @retry_strategies = [retry_new_strategy, retry_failed_strategy, no_retries_strategy]
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

        def record_test_finished(test_span)
          if current_retry_driver.nil?
            # we always run test at least once and after the first pass create a correct retry driver
            self.current_retry_driver = build_driver(test_span)
          else
            # after each retry we record the result, the driver will decide if we should retry again
            current_retry_driver&.record_retry(test_span)
          end
        end

        def record_test_span_duration(tracer_span)
          current_retry_driver&.record_duration(tracer_span.duration)
        end

        # this API is targeted on Cucumber instrumentation or any other that cannot leverage #with_retries method
        def reset_retries!
          self.current_retry_driver = nil
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
