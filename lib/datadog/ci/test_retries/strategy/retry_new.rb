# frozen_string_literal: true

require_relative "base"

require_relative "../../ext/test"

module Datadog
  module CI
    module TestRetries
      module Strategy
        # retry every new test up to 10 times (early flake detection)
        class RetryNew < Base
          def initialize(test_span, duration_thresholds:)
            @duration_thresholds = duration_thresholds
            @attempts = 0
            # will be changed based on test span duration
            @max_attempts = 10

            mark_new_test(test_span)
          end

          def should_retry?
            @attempts < @max_attempts
          end

          def record_retry(test_span)
            super

            @attempts += 1
            mark_new_test(test_span)

            Datadog.logger.debug { "Retry Attempts [#{@attempts} / #{@max_attempts}]" }
          end

          def record_duration(duration)
            @max_attempts = @duration_thresholds.max_attempts_for_duration(duration)

            Datadog.logger.debug { "Recorded test duration of [#{duration}], new Max Attempts value is [#{@max_attempts}]" }
          end

          private

          def mark_new_test(test_span)
            test_span.set_tag(Ext::Test::TAG_IS_NEW, "true")
          end
        end
      end
    end
  end
end
