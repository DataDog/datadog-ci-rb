# frozen_string_literal: true

require_relative "base"

require_relative "../driver/retry_failed"
require_relative "../driver/retry_failed_dynamic"

module Datadog
  module CI
    module TestRetries
      module Strategy
        class RetryFailed < Base
          attr_reader :enabled, :max_attempts,
            :total_limit, :retried_count

          def initialize(
            enabled:,
            max_attempts:,
            total_limit:,
            dynamic_atr_enabled:,
            dynamic_atr_buckets:
          )
            @enabled = enabled
            @max_attempts = max_attempts
            @total_limit = total_limit
            @retried_count = 0
            @dynamic_atr_enabled = dynamic_atr_enabled
            @dynamic_atr_buckets = dynamic_atr_buckets
            @slow_test_retries = nil
          end

          def covers?(test_span)
            return false unless @enabled

            if @retried_count >= @total_limit
              Datadog.logger.debug do
                "Retry failed tests limit reached: [#{@retried_count}] out of [#{@total_limit}]"
              end
              @enabled = false
            end

            @enabled && !!test_span&.failed?
          end

          def configure(library_settings, test_session)
            @enabled &&= library_settings.flaky_test_retries_enabled?
            @slow_test_retries = library_settings.slow_test_retries if @dynamic_atr_enabled
          end

          def build_driver(test_span)
            Datadog.logger.debug { "#{test_span.name} failed, will be retried" }

            @retried_count += 1

            slow_test_retries = @slow_test_retries
            return Driver::RetryFailed.new(max_attempts: max_attempts) unless @dynamic_atr_enabled && slow_test_retries

            Driver::RetryFailedDynamic.new(
              slow_test_retries,
              retries_buckets: @dynamic_atr_buckets
            )
          end
        end
      end
    end
  end
end
