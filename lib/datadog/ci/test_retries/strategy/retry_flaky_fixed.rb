# frozen_string_literal: true

require_relative "base"

require_relative "../driver/retry_flaky_fixed"
require_relative "../../ext/settings"

module Datadog
  module CI
    module TestRetries
      module Strategy
        # This strategy retries tests that are flaky and were marked as attempted to be fixed in Datadog Test Management UI.
        class RetryFlakyFixed < Base
          attr_reader :enabled, :max_attempts

          def initialize(
            enabled:,
            max_attempts:
          )
            @enabled = enabled
            @configured_max_attempts = max_attempts
            @max_attempts = max_attempts || Ext::Settings::DEFAULT_TEST_MANAGEMENT_ATTEMPT_TO_FIX_RETRIES
          end

          def configure(library_settings, test_session)
            @enabled &&= library_settings.test_management_enabled?
            @max_attempts = @configured_max_attempts || library_settings.attempt_to_fix_retries_count ||
              Ext::Settings::DEFAULT_TEST_MANAGEMENT_ATTEMPT_TO_FIX_RETRIES
          end

          def covers?(test_span)
            return false unless @enabled

            !!test_span&.should_retry_attempt_to_fix?
          end

          def build_driver(test_span)
            Datadog.logger.debug { "#{test_span.name} is attempt_to_fix, will be retried" }

            Driver::RetryFlakyFixed.new(test_span, max_attempts: max_attempts)
          end
        end
      end
    end
  end
end
