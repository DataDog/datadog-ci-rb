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
              @datadog_formatter ||= Formatter.new(@configuration)
              [@datadog_formatter] + existing_formatters
            end

            def filters
              require_relative "filter"

              filters_list = super
              datadog_filter = Filter.new(@configuration)
              unless @configuration.dry_run?
                # insert our filter the pre-last position because Cucumber::Filters::PrepareWorld must be the last one
                # see:
                # https://github.com/cucumber/cucumber-ruby/blob/58dd8f12c0ac5f4e607335ff2e7d385c1ed25899/lib/cucumber/runtime.rb#L266
                filters_list.insert(-2, datadog_filter)
              end
              filters_list
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
