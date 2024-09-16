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

          def record_retry(test_span)
            test_span&.set_tag(Ext::Test::TAG_IS_RETRY, "true")
          end

          # duration in float seconds
          def record_duration(duration)
          end
        end
      end
    end
  end
end
