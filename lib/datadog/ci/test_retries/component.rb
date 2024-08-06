# frozen_string_literal: true

require_relative "strategy/no_retry"

module Datadog
  module CI
    module TestRetries
      # Encapsulates the logic to enable test retries, including:
      # - retrying failed tests - improve success rate of CI pipelines
      # - retrying new tests - detect flaky tests as early as possible to prevent them from being merged
      class Component
        attr_reader :retry_failed_tests_enabled, :retry_failed_tests_max_attempts, :retry_failed_tests_total_limit

        def initialize(
          retry_failed_tests_max_attempts:,
          retry_failed_tests_total_limit:
        )
          # enabled only by remote settings
          @retry_failed_tests_enabled = false
          @retry_failed_tests_max_attempts = retry_failed_tests_max_attempts
          @retry_failed_tests_total_limit = retry_failed_tests_total_limit

          # TODO: increment in #build_strategy method if test failed and should be retried
          @retry_failed_tests_count = 0
        end

        def configure(library_settings)
          @retry_failed_tests_enabled = library_settings.flaky_test_retries_enabled?
        end

        def with_retries(&block)
          retry_strategy = nil

          finished_proc = proc do |test_span|
            if retry_strategy.nil?
              retry_strategy = Strategy::NoRetry.new
            else
              retry_strategy.track_retry(test_span)
            end
          end

          loop do
            yield finished_proc

            break unless retry_strategy&.should_retry?
          end
        end
      end
    end
  end
end
