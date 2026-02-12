# frozen_string_literal: true

require_relative "base"

require_relative "../../ext/test"

module Datadog
  module CI
    module TestRetries
      module Driver
        # Retries tests marked as "attempt to fix" to verify the fix works consistently.
        # Stops early after the first failed execution (fix did not work).
        class RetryFlakyFixed < Base
          attr_reader :max_attempts

          def initialize(test_span, max_attempts:)
            @attempts = 0
            @max_attempts = max_attempts
            @failed_once = !!test_span&.failed?
          end

          def should_retry?
            @attempts < @max_attempts && !@failed_once
          end

          def record_retry(test_span)
            super

            @attempts += 1
            @failed_once = true if test_span&.failed?

            Datadog.logger.debug { "Retry Attempts [#{@attempts} / #{@max_attempts}], Failed: [#{@failed_once}]" }
          end

          def retry_reason
            Ext::Test::RetryReason::RETRY_FLAKY_FIXED
          end
        end
      end
    end
  end
end
