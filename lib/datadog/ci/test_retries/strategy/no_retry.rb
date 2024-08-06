# frozen_string_literal: true

require_relative "base"

module Datadog
  module CI
    module TestRetries
      module Strategy
        class NoRetry < Base
        end
      end
    end
  end
end
