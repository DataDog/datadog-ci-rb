# frozen_string_literal: true

require_relative "base"

require_relative "../../ext/test"

module Datadog
  module CI
    module TestRetries
      module Driver
        class RetryFailed < Base
          attr_reader :max_attempts

          def initialize(max_attempts:)
            @max_attempts = max_attempts

            @attempts = 0
            @passed_once = false
          end

          def should_retry?
            @attempts < @max_attempts && !@passed_once
          end

          def record_retry(test_span)
            super

            @attempts += 1
            @passed_once = true if test_span&.passed?

            Datadog.logger.debug { "Retry Attempts [#{@attempts} / #{@max_attempts}], Passed: [#{@passed_once}]" }
          end

          def retry_reason
            Ext::Test::RetryReason::RETRY_FAILED
          end
        end
      end
    end
  end
end
