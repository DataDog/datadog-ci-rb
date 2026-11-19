# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Lograge
        module LogSubscriber
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            private

            def before_format(data, payload)
              return super unless datadog_logs_component.enabled
              return super unless datadog_configuration[:enabled]

              result = super

              if result.fetch(:dd, {}).fetch(:trace_id, nil).nil?
                Datadog::CI.logger.debug { "Discarding uncorrelated log event: #{result.inspect}" }
                return result
              end
              datadog_logs_component.write(result)
              result
            end

            def datadog_logs_component
              Datadog::CI.components.agentless_logs_submission
            end

            def datadog_configuration
              Datadog::CI.configuration.ci[:lograge]
            end
          end
        end
      end
    end
  end
end
