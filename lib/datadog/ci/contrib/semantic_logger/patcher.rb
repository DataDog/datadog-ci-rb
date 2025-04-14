# frozen_string_literal: true

require_relative "../patcher"
require_relative "logger"

module Datadog
  module CI
    module Contrib
      module SemanticLogger
        # Patcher enables patching of semantic_logger module
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            unless datadog_logs_component.enabled
              Datadog.logger.debug("Datadog logs submission is disabled, skipping semantic_logger patching")
              return
            end

            ::SemanticLogger::Logger.include(Logger)
          end

          def datadog_logs_component
            Datadog.send(:components).agentless_logs_submission
          end
        end
      end
    end
  end
end
