# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module SemanticLogger
        module Logger
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def log(log, message = nil, progname = nil, &block)
              return super unless log.is_a?(::SemanticLogger::Log)
              return super unless datadog_logs_component.enabled

              result = super

              datadog_logs_component.write(log.to_h.clone)

              result
            end

            def datadog_logs_component
              Datadog.send(:components).agentless_logs_submission
            end
          end
        end
      end
    end
  end
end
