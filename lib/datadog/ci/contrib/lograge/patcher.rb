# frozen_string_literal: true

require_relative "../patcher"
require_relative "log_subscriber"

module Datadog
  module CI
    module Contrib
      module Lograge
        # Patcher enables patching of lograge module
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            unless datadog_logs_component.enabled
              Datadog.logger.debug("Datadog logs submission is disabled, skipping lograge patching")
              return
            end

            ::Lograge::LogSubscribers::Base.include(LogSubscriber)
          end

          def datadog_logs_component
            Datadog.send(:components).agentless_logs_submission
          end
        end
      end
    end
  end
end
