# frozen_string_literal: true

require_relative "../driver/no_retry"

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
            total_limit:
          )
            @enabled = enabled
            @max_attempts = max_attempts
            @total_limit = total_limit
            @retried_count = 0
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
          end

          def build_driver(test_span)
            Datadog.logger.debug { "#{test_span.name} failed, will be retried" }

            @retried_count += 1

            Driver::RetryFailed.new(max_attempts: max_attempts)
          end
        end
      end
    end
  end
end
