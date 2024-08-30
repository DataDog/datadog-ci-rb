# frozen_string_literal: true

require_relative "strategy/no_retry"
require_relative "strategy/retry_failed"

module Datadog
  module CI
    module TestRetries
      # Encapsulates the logic to enable test retries, including:
      # - retrying failed tests - improve success rate of CI pipelines
      # - retrying new tests - detect flaky tests as early as possible to prevent them from being merged
      class Component
        attr_reader :retry_failed_tests_enabled, :retry_failed_tests_max_attempts,
          :retry_failed_tests_total_limit, :retry_failed_tests_count,
          :retry_new_tests_enabled

        def initialize(
          retry_failed_tests_enabled:,
          retry_failed_tests_max_attempts:,
          retry_failed_tests_total_limit:,
          retry_new_tests_enabled:
        )
          @retry_failed_tests_enabled = retry_failed_tests_enabled
          @retry_failed_tests_max_attempts = retry_failed_tests_max_attempts
          @retry_failed_tests_total_limit = retry_failed_tests_total_limit
          # counter that stores the current number of failed tests retried
          @retry_failed_tests_count = 0

          @retry_new_tests_enabled = retry_new_tests_enabled

          @mutex = Mutex.new
        end

        def configure(library_settings)
          @retry_failed_tests_enabled &&= library_settings.flaky_test_retries_enabled?
          @retry_new_tests_enabled &&= library_settings.early_flake_detection_enabled?
        end

        def with_retries(&block)
          # @type var retry_strategy: Strategy::Base
          retry_strategy = nil

          test_finished_callback = lambda do |test_span|
            if retry_strategy.nil?
              # we always run test at least once and after first pass create a correct retry strategy
              retry_strategy = build_strategy(test_span)
            else
              # after each retry we record the result, strategy will decide if we should retry again
              retry_strategy&.record_retry(test_span)
            end
          end

          test_visibility_component.set_test_finished_callback(test_finished_callback)

          loop do
            yield

            break unless retry_strategy&.should_retry?
          end
        ensure
          test_visibility_component.remove_test_finished_callback
        end

        def build_strategy(test_span)
          @mutex.synchronize do
            if should_retry_failed_test?(test_span)
              Datadog.logger.debug("Failed test retry starts")
              @retry_failed_tests_count += 1

              Strategy::RetryFailed.new(max_attempts: @retry_failed_tests_max_attempts)
            else
              Strategy::NoRetry.new
            end
          end
        end

        private

        def should_retry_failed_test?(test_span)
          @retry_failed_tests_enabled && !!test_span&.failed? && @retry_failed_tests_count < @retry_failed_tests_total_limit
        end

        def test_visibility_component
          Datadog.send(:components).test_visibility
        end
      end
    end
  end
end
