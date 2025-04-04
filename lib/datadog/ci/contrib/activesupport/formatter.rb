# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module ActiveSupport
        module Formatter
          def call(severity, timestamp, progname, msg)
            # don't even construct an object for every log message if agentless logs submission is not enabled
            super unless datadog_logs_component.enabled

            datadog_logs_component.write({
              message: msg,
              level: severity
            })

            super
          end

          def datadog_logs_component
            Datadog.send(:components).agentless_logs_submission
          end
        end
      end
    end
  end
end
