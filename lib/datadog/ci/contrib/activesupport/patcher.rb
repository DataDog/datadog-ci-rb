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

            # Before Ruby 3.0, prepending to a module did not change existing instances where this module was included
            # It means that for Ruby 2.7 we have to patch formatter's class directly
            #
            # Context:
            # - https://bugs.ruby-lang.org/issues/9573
            # - https://rubyreferences.github.io/rubychanges/3.0.html#include-and-prepend-now-affects-modules-including-the-receiver
            if RUBY_VERSION.start_with?("2.7")
              Rails.logger.formatter.class.prepend(LogsFormatter)
            else
              ::ActiveSupport::TaggedLogging::Formatter.prepend(LogsFormatter)
            end
          end

          def datadog_logs_component
            Datadog.send(:components).agentless_logs_submission
          end
        end
      end
    end
  end
end
