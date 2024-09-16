# frozen_string_literal: true

require_relative "base"

module Datadog
  module CI
    module TestRetries
      module Driver
        class NoRetry < Base
          def record_retry(test_span)
          end
        end
      end
    end
  end
end
