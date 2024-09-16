# frozen_string_literal: true

require_relative "driver/no_retry"
require_relative "driver/retry_failed"
require_relative "driver/retry_new"

require_relative "../ext/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module TestRetries
      # Encapsulates the logic to enable test retries, including:
      # - retrying failed tests - improve success rate of CI pipelines
      # - retrying new tests - detect flaky tests as early as possible to prevent them from being merged
      class Component
        FIBER_LOCAL_CURRENT_RETRY_STRATEGY_KEY = :__dd_current_retry_strategy

        DEFAULT_TOTAL_TESTS_COUNT = 100

        # there are clearly 2 different concepts mixed here, we should split them into separate components
        # (high level strategies?) in the subsequent PR
        attr_reader :retry_failed_tests_enabled, :retry_failed_tests_max_attempts,
          :retry_failed_tests_total_limit, :retry_failed_tests_count,
          :retry_new_tests_enabled, :retry_new_tests_duration_thresholds, :retry_new_tests_unique_tests_set,
          :retry_new_tests_total_limit, :retry_new_tests_count

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
          @retry_new_tests_unique_tests_set = Set.new
          @unique_tests_client = unique_tests_client
          # total maximum number of new tests to retry (will be set based on the total number of tests in the session)
          @retry_new_tests_total_limit = 0
          # counter thate stores the current number of new tests retried
          @retry_new_tests_count = 0

          @mutex = Mutex.new
        end

        def configure(library_settings, test_session)
          @retry_failed_tests_enabled &&= library_settings.flaky_test_retries_enabled?
          @retry_new_tests_enabled &&= library_settings.early_flake_detection_enabled?

          return unless @retry_new_tests_enabled

          # mark early flake detection enabled for test session
          test_session.set_tag(Ext::Test::TAG_EARLY_FLAKE_ENABLED, "true")

          # configure retrying new tests
          @retry_new_tests_duration_thresholds = library_settings.slow_test_retries
          Datadog.logger.debug do
            "Slow test retries thresholds: #{@retry_new_tests_duration_thresholds.entries}"
          end

          @retry_new_tests_unique_tests_set = @unique_tests_client.fetch_unique_tests(test_session)

          percentage_limit = library_settings.faulty_session_threshold
          tests_count = test_session.total_tests_count.to_i
          if tests_count.zero?
            Datadog.logger.debug do
              "Total tests count is zero, using default value for the total number of tests: [#{DEFAULT_TOTAL_TESTS_COUNT}]"
            end

            tests_count = DEFAULT_TOTAL_TESTS_COUNT
          end

          @retry_new_tests_total_limit = (tests_count * percentage_limit / 100.0).ceil
          Datadog.logger.debug do
            "Retry new tests total limit is [#{@retry_new_tests_total_limit}] (#{percentage_limit}%) of #{tests_count}"
          end

          if @retry_new_tests_unique_tests_set.empty?
            @retry_new_tests_enabled = false
            mark_test_session_faulty(test_session)

            Datadog.logger.warn(
              "Disabling early flake detection because there is no known tests (possible reason: no test runs in default branch)"
            )
          end

          Datadog.logger.debug do
            "Found [#{@retry_new_tests_unique_tests_set.size}] known unique tests"
          end
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_EFD_UNIQUE_TESTS_RESPONSE_TESTS,
            @retry_new_tests_unique_tests_set.size.to_f
          )
        end

        def with_retries(&block)
          self.current_retry_strategy = nil

          loop do
            yield

            break unless current_retry_strategy&.should_retry?
          end
        ensure
          self.current_retry_strategy = nil
        end

        def build_strategy(test_span)
          @mutex.synchronize do
            if should_retry_new_test?(test_span)
              Datadog.logger.debug do
                "#{test_span.name} is new, will be retried"
              end
              @retry_new_tests_count += 1

              Driver::RetryNew.new(test_span, duration_thresholds: @retry_new_tests_duration_thresholds)
            elsif should_retry_failed_test?(test_span)
              Datadog.logger.debug do
                "#{test_span.name} failed, will be retried"
              end
              @retry_failed_tests_count += 1

              Driver::RetryFailed.new(max_attempts: @retry_failed_tests_max_attempts)
            else
              Driver::NoRetry.new
            end
          end
        end

        def record_test_finished(test_span)
          if current_retry_strategy.nil?
            # we always run test at least once and after the first pass create a correct retry strategy
            self.current_retry_strategy = build_strategy(test_span)
          else
            # after each retry we record the result, strategy will decide if we should retry again
            current_retry_strategy&.record_retry(test_span)
          end
        end

        def record_test_span_duration(tracer_span)
          current_retry_strategy&.record_duration(tracer_span.duration)
        end

        private

        def current_retry_strategy
          Thread.current[FIBER_LOCAL_CURRENT_RETRY_STRATEGY_KEY]
        end

        def current_retry_strategy=(strategy)
          Thread.current[FIBER_LOCAL_CURRENT_RETRY_STRATEGY_KEY] = strategy
        end

        def should_retry_failed_test?(test_span)
          return false unless @retry_failed_tests_enabled

          if @retry_failed_tests_count >= @retry_failed_tests_total_limit
            Datadog.logger.debug do
              "Retry failed tests limit reached: [#{@retry_failed_tests_count}] out of [#{@retry_new_tests_total_limit}]"
            end
            @retry_failed_tests_enabled = false
          end

          @retry_failed_tests_enabled && !!test_span&.failed?
        end

        def should_retry_new_test?(test_span)
          return false unless @retry_new_tests_enabled

          if @retry_new_tests_count >= @retry_new_tests_total_limit
            Datadog.logger.debug do
              "Retry new tests limit reached: [#{@retry_new_tests_count}] out of [#{@retry_new_tests_total_limit}]"
            end
            @retry_new_tests_enabled = false
            mark_test_session_faulty(Datadog::CI.active_test_session)
          end

          @retry_new_tests_enabled && !test_span.skipped? && is_new_test?(test_span)
        end

        def test_visibility_component
          Datadog.send(:components).test_visibility
        end

        def is_new_test?(test_span)
          test_id = Utils::TestRun.datadog_test_id(test_span.name, test_span.test_suite_name)

          result = !@retry_new_tests_unique_tests_set.include?(test_id)

          if result
            Datadog.logger.debug do
              "#{test_id} is not found in the unique tests set, it is a new test"
            end
          end

          result
        end

        def mark_test_session_faulty(test_session)
          test_session&.set_tag(Ext::Test::TAG_EARLY_FLAKE_ABORT_REASON, Ext::Test::EARLY_FLAKE_FAULTY)
        end
      end
    end
  end
end
