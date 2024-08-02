# frozen_string_literal: true

module Datadog
  module CI
    module TestRetries
      # Encapsulates the logic to enable test retries, including:
      # - retrying failed tests - improve success rate of CI pipelines
      # - retrying new tests - detect flaky tests as early as possible to prevent them from being merged
      class Component
        attr_reader :retry_failed_tests_enabled, :retry_failed_tests_max_attempts

        def initialize(retry_failed_tests_max_attempts:)
          # enabled only by remote settings
          @retry_failed_tests_enabled = false
          @retry_failed_tests_max_attempts = retry_failed_tests_max_attempts
        end

        def configure(library_settings)
          @retry_failed_tests_enabled = library_settings.flaky_test_retries_enabled?
        end
      end
    end
  end
end
