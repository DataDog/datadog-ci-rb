# frozen_string_literal: true

module Datadog
  module CI
    module TestRetries
      module Driver
        # Driver is the class responsible for the current test retry mechanism.
        # It receives signals about each retry execution and steers the current retry strategy.
        class Base
          def should_retry?
            false
          end

          def mark_as_retry(test_span)
            test_span&.set_tag(Ext::Test::TAG_IS_RETRY, "true")
            test_span&.set_tag(Ext::Test::TAG_RETRY_REASON, retry_reason)
          end

          def record_retry(test_span)
          end

          # duration in float seconds
          def record_duration(duration)
          end

          def retry_reason
            # we set retry reason to be external (ie retried outside of datadog)
            # by default if we don't know why the test was retried
            Ext::Test::RetryReason::RETRY_EXTERNAL
          end
        end
      end
    end
  end
end
