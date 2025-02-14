# frozen_string_literal: true

require_relative "base"

require_relative "../driver/retry_new"

module Datadog
  module CI
    module TestRetries
      module Strategy
        class RetryNew < Base
          DEFAULT_TOTAL_TESTS_COUNT = 100

          attr_reader :enabled, :max_attempts_thresholds, :total_limit, :retried_count

          def initialize(enabled:)
            @enabled = enabled
            # total maximum number of new tests to retry (will be set based on the total number of tests in the session)
            @total_limit = 0
            @retried_count = 0
          end

          def covers?(test_span)
            return false unless @enabled

            if @retried_count >= @total_limit
              Datadog.logger.debug do
                "Retry new tests limit reached: [#{@retried_count}] out of [#{@total_limit}]"
              end
              @enabled = false
              mark_test_session_faulty(Datadog::CI.active_test_session)
            end

            @enabled && !test_span.skipped? && test_span.is_new?
          end

          def configure(library_settings, test_session)
            @enabled &&= library_settings.early_flake_detection_enabled? && library_settings.known_tests_enabled?

            return unless @enabled

            # mark early flake detection enabled for test session
            test_session.set_tag(Ext::Test::TAG_EARLY_FLAKE_ENABLED, "true")

            set_max_attempts_thresholds(library_settings)
            calculate_total_retries_limit(library_settings, test_session)
          end

          def build_driver(test_span)
            Datadog.logger.debug do
              "#{test_span.name} is new, will be retried"
            end
            @retried_count += 1

            Driver::RetryNew.new(test_span, max_attempts_thresholds: @max_attempts_thresholds)
          end

          private

          def mark_test_session_faulty(test_session)
            test_session&.set_tag(Ext::Test::TAG_EARLY_FLAKE_ABORT_REASON, Ext::Test::EARLY_FLAKE_FAULTY)
          end

          def set_max_attempts_thresholds(library_settings)
            @max_attempts_thresholds = library_settings.slow_test_retries
            Datadog.logger.debug do
              "Slow test retries thresholds: #{@max_attempts_thresholds.entries}"
            end
          end

          def calculate_total_retries_limit(library_settings, test_session)
            percentage_limit = library_settings.faulty_session_threshold
            tests_count = test_session.total_tests_count.to_i
            if tests_count.zero?
              Datadog.logger.debug do
                "Total tests count is zero, using default value for the total number of tests: [#{DEFAULT_TOTAL_TESTS_COUNT}]"
              end

              tests_count = DEFAULT_TOTAL_TESTS_COUNT
            end
            @total_limit = (tests_count * percentage_limit / 100.0).ceil
            Datadog.logger.debug do
              "Retry new tests total limit is [#{@total_limit}] (#{percentage_limit}% of #{tests_count})"
            end
          end
        end
      end
    end
  end
end
