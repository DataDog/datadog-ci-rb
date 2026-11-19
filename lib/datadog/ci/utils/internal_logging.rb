# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module InternalLogging
        def self.error(message)
          CI.logger.error(message)
        end

        def self.report(error, description: nil, **_options)
          CI.logger.warn("#{description}: #{error.class}: #{error.message}")
        end
      end
    end
  end
end
