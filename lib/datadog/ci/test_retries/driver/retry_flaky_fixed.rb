# frozen_string_literal: true

require_relative "base"

require_relative "../../ext/test"

module Datadog
  module CI
    module TestRetries
      module Driver
        class RetryFlakyFixed < Base
          attr_reader :max_attempts

          def initialize(max_attempts:)
            @attempts = 0
            @max_attempts = max_attempts
          end

          def should_retry?
            @attempts < @max_attempts
          end

          def record_retry(test_span)
            super

            @attempts += 1

            Datadog.logger.debug { "Retry Attempts [#{@attempts} / #{@max_attempts}]" }
          end

          def retry_reason
            Ext::Test::RetryReason::RETRY_FLAKY_FIXED
          end
        end
      end
    end
  end
end
