# frozen_string_literal: true

require_relative "../patcher"
require_relative "logs_formatter"

module Datadog
  module CI
    module Contrib
      module ActiveSupport
        # Patcher enables patching of activesupport module
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            unless datadog_logs_component.enabled
              Datadog.logger.debug("Datadog logs submission is disabled, skipping activesupport patching")
              return
            end

            unless ::Rails.logger.formatter.is_a?(::ActiveSupport::TaggedLogging::Formatter)
              Datadog.logger.debug {
                "Rails logger formatter is not an instance of ActiveSupport::TaggedLogging::Formatter, skipping activesupport patching. " \
                "Formatter: #{::Rails.logger.formatter.class}"
              }
              return
            end

            ::ActiveSupport::TaggedLogging::Formatter.prepend(LogsFormatter)
          end

          def datadog_logs_component
            Datadog.send(:components).agentless_logs_submission
          end
        end
      end
    end
  end
end
