# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module ActiveSupport
        module LogsFormatter
          def call(severity, timestamp, progname, msg)
            # don't even construct an object for every log message if agentless logs submission is not enabled
            return super unless datadog_logs_component.enabled

            # additional precaution because we cannot use targeted prepend in Ruby 2.7, so method :tags_text might
            # not be available (highly unlikely, but not unimaginable)
            #
            # (see Datadog::CI::Contrib::ActiveSupport::Patcher for explanation)
            return super unless respond_to?(:tags_text)

            message = "#{msg} #{tags_text}"
            return super unless message.include?("dd.trace_id")

            datadog_logs_component.write({
              message: message,
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
