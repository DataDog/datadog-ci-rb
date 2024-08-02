# frozen_string_literal: true

require_relative "formatter"

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Instrumentation for Cucumber::Runtime class
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

            def begin_scenario(test_case)
              if Datadog::CI.active_test&.skipped_by_itr?
                raise ::Cucumber::Core::Test::Result::Skipped, CI::Ext::Test::ITR_TEST_SKIP_REASON
              end

              super
            end
          end
        end
      end
    end
  end
end
