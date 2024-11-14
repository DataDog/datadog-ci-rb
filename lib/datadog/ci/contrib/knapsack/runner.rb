# frozen_string_literal: true

require_relative "../../../ext/test"
require_relative "../ext"
require_relative "../instrumentation"

module Datadog
  module CI
    module Contrib
      module Knapsack
        module Runner
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            # TODO: this is coupled to RSpec integration being present, not sure if it's bad or not at this point
            def knapsack__run_specs(*args)
              return super if ::RSpec.configuration.dry_run? && !datadog_configuration[:dry_run_enabled]
              return super unless datadog_configuration[:enabled]

              test_session = test_visibility_component.start_test_session(
                tags: {
                  CI::Ext::Test::TAG_FRAMEWORK => CI::Contrib::RSpec::Ext::FRAMEWORK,
                  CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s
                },
                service: datadog_configuration[:service_name]
              )

              test_module = test_visibility_component.start_test_module(CI::Contrib::RSpec::Ext::FRAMEWORK)

              result = super
              return result unless test_module && test_session

              if result != 0
                test_module.failed!
                test_session.failed!
              else
                test_module.passed!
                test_session.passed!
              end
              test_module.finish
              test_session.finish

              result
            end

            private

            def datadog_integration
              CI::Contrib::Instrumentation.fetch_integration(:rspec)
            end

            def datadog_configuration
              Datadog.configuration.ci[:rspec]
            end

            def test_visibility_component
              Datadog.send(:components).test_visibility
            end
          end
        end
      end
    end
  end
end
