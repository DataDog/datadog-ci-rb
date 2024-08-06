# frozen_string_literal: true

module Datadog
  module CI
    module TestRetries
      module Strategy
        class Base
          def should_retry?
            false
          end

          def track_retry(test_span)
          end
        end
      end
    end
  end
end
