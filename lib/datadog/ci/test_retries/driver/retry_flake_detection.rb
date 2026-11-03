# frozen_string_literal: true

require_relative "base"

require_relative "../../ext/test"

module Datadog
  module CI
    module TestRetries
      module Driver
        # repeat new tests within the configured total execution budget (early flake detection)
        # stop early once both a pass and a fail have been observed (flakiness confirmed)
        class RetryFlakeDetection < Base
          def initialize(test_span, max_attempts_thresholds:)
            @max_attempts_thresholds = max_attempts_thresholds
            @attempts = 0
            @max_attempts = 0
            @duration_recorded = false
            @test_span = test_span

            # track outcomes to stop early once flakiness is confirmed
            @passed_once = !!test_span&.passed?
            @failed_once = !!test_span&.failed?
          end

          def should_retry?
            @attempts < @max_attempts && !flakiness_detected?
          end

          def record_retry(test_span)
            super

            @attempts += 1
            @passed_once = true if test_span&.passed?
            @failed_once = true if test_span&.failed?

            Datadog.logger.debug { "Retry Attempts [#{@attempts} / #{@max_attempts}], Passed: [#{@passed_once}], Failed: [#{@failed_once}]" }
          end

          def record_duration(duration)
            return if @duration_recorded

            total_executions = @max_attempts_thresholds.max_attempts_for_duration(duration)
            @max_attempts = [total_executions - 1, 0].max
            @duration_recorded = true
            if total_executions.zero?
              @test_span.set_internal_tag(Ext::Test::TAG_EARLY_FLAKE_ABORT_REASON, Ext::Test::EARLY_FLAKE_SLOW)
            end

            Datadog.logger.debug { "Recorded test duration of [#{duration}], new Max Attempts value is [#{@max_attempts}]" }
          end

          def retry_reason
            Ext::Test::RetryReason::RETRY_DETECT_FLAKY
          end

          private

          def flakiness_detected?
            @passed_once && @failed_once
          end
        end
      end
    end
  end
end
