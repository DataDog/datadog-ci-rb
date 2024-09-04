# frozen_string_literal: true

require_relative "strategy/no_retry"
require_relative "strategy/retry_failed"

require_relative "../ext/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module TestRetries
      # Encapsulates the logic to enable test retries, including:
      # - retrying failed tests - improve success rate of CI pipelines
      # - retrying new tests - detect flaky tests as early as possible to prevent them from being merged
      class Component
        attr_reader :retry_failed_tests_enabled, :retry_failed_tests_max_attempts,
          :retry_failed_tests_total_limit, :retry_failed_tests_count,
          :retry_new_tests_enabled, :retry_new_tests_duration_thresholds, :retry_new_tests_percentage_limit,
          :retry_new_tests_unique_tests_set, :retry_new_tests_fault_reason

        def initialize(
          retry_failed_tests_enabled:,
          retry_failed_tests_max_attempts:,
          retry_failed_tests_total_limit:,
          retry_new_tests_enabled:,
          unique_tests_client:
        )
          @retry_failed_tests_enabled = retry_failed_tests_enabled
          @retry_failed_tests_max_attempts = retry_failed_tests_max_attempts
          @retry_failed_tests_total_limit = retry_failed_tests_total_limit
          # counter that stores the current number of failed tests retried
          @retry_failed_tests_count = 0

          @retry_new_tests_enabled = retry_new_tests_enabled
          @retry_new_tests_duration_thresholds = nil
          @retry_new_tests_percentage_limit = 0
          @retry_new_tests_unique_tests_set = Set.new
          # indicates that retrying new tests failed and was disabled
          @retry_new_tests_fault_reason = nil

          @unique_tests_client = unique_tests_client

          @mutex = Mutex.new
        end

        def configure(library_settings, test_session)
          @retry_failed_tests_enabled &&= library_settings.flaky_test_retries_enabled?
          @retry_new_tests_enabled &&= library_settings.early_flake_detection_enabled?

          return unless @retry_new_tests_enabled

          # configure retrying new tests
          @retry_new_tests_duration_thresholds = library_settings.slow_test_retries
          @retry_new_tests_percentage_limit = library_settings.faulty_session_threshold
          @retry_new_tests_unique_tests_set = @unique_tests_client.fetch_unique_tests(test_session)

          if @retry_new_tests_unique_tests_set.empty?
            @retry_new_tests_enabled = false
            @retry_new_tests_fault_reason = "unique tests set is empty"

            Datadog.logger.debug("Unique tests set is empty, retrying new tests disabled")
          else
            Utils::Telemetry.distribution(
              Ext::Telemetry::METRIC_EFD_UNIQUE_TESTS_RESPONSE_TESTS,
              @retry_new_tests_unique_tests_set.size.to_f
            )
          end
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

          # TODO: is there a better way to let test_visibility_component know that we are running under retries component?
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
