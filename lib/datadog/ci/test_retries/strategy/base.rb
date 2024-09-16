# frozen_string_literal: true

require_relative "../driver/no_retry"

module Datadog
  module CI
    module TestRetries
      module Strategy
        # Strategies are subcomponents of the retry mechanism. They are responsible for
        # determining which tests should be retried and how.
        class Base
          def covers?(test_span)
            true
          end

          def configure(_library_settings, _test_session)
          end

          def build_driver(_test_span)
            Driver::NoRetry.new
          end
        end
      end
    end
  end
end
