# frozen_string_literal: true

require_relative "base"

require_relative "../../ext/test"

module Datadog
  module CI
    module TestRetries
      module Driver
        # Dynamic ATR driver: retries failing tests using duration-based retry budgets
        # instead of the flat per-test retry limit. The test is classified once by its
        # initial-attempt duration, and the resulting max-retries count is cached for
        # the lifetime of that test.
        class RetryFailedDynamic < Base
          attr_reader :max_attempts

          def initialize(slow_test_retries, retries_buckets: nil)
            @slow_test_retries = slow_test_retries
            @retries_buckets = retries_buckets
            @attempts = 0
            @passed_once = false
            @max_attempts = 1
            @duration_recorded = false
          end

          def should_retry?
            @attempts < @max_attempts && !@passed_once
          end

          def record_retry(test_span)
            super

            @attempts += 1
            @passed_once = true if test_span&.passed?

            Datadog.logger.debug { "Dynamic ATR Attempts [#{@attempts} / #{@max_attempts}], Passed: [#{@passed_once}]" }
          end

          # Classify the test once based on the initial-attempt duration.
          # Subsequent calls (from retries) are ignored — the first classification sticks.
          def record_duration(duration)
            return if @duration_recorded

            if (retries_buckets = @retries_buckets)
              index = @slow_test_retries.retry_bucket_index_for_duration(duration)
              @max_attempts = [1, retries_buckets.fetch(index)].max
            else
              @max_attempts = [1, @slow_test_retries.retries_for_duration(duration)].max
            end
            @duration_recorded = true

            Datadog.logger.debug { "Dynamic ATR: duration [#{duration}s], max attempts [#{@max_attempts}]" }
          end

          def retry_reason
            Ext::Test::RetryReason::RETRY_FAILED
          end
        end
      end
    end
  end
end
