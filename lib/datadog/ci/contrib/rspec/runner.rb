# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../instrumentation"
require_relative "ext"
require_relative "helpers"

module Datadog
  module CI
    module Contrib
      module RSpec
        # Instrument RSpec::Core::Runner
        module Runner
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def run_specs(*args)
              return super if ::RSpec.configuration.dry_run? && !datadog_configuration[:dry_run_enabled]
              return super unless datadog_configuration[:enabled]

              test_session = test_visibility_component.start_test_session(
                tags: {
                  CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                  CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s
                },
                service: datadog_configuration[:service_name],
                estimated_total_tests_count: ::RSpec.world.example_count
              )

              test_module = test_visibility_component.start_test_module(Ext::FRAMEWORK)

              result = super
              return result unless test_module && test_session
              return result if Helpers.parallel_tests?

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
