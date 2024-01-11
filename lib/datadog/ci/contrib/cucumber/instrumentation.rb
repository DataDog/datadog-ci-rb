# frozen_string_literal: true

require_relative "formatter"

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Instrumentation for Cucumber
        module Instrumentation
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          # Instance methods for configuration
          module InstanceMethods
            attr_reader :datadog_formatter

            def formatters
              existing_formatters = super
              @datadog_formatter ||= CI::Contrib::Cucumber::Formatter.new(@configuration)
              [@datadog_formatter] + existing_formatters
            end
          end
        end
      end
    end
  end
end
