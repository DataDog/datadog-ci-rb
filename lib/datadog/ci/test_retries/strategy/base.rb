# frozen_string_literal: true

module Datadog
  module CI
    module TestRetries
      module Strategy
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
