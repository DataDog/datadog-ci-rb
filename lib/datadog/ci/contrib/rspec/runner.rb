# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../instrumentation"
require_relative "ext"

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
              return super unless datadog_configuration[:enabled]

              discovery_component = test_discovery_component

              if discovery_component&.enabled?
                discover_tests(discovery_component)

                # don't run the tests, we just needed to discover them and now we can return
                return
              end

              return super if ::RSpec.configuration.dry_run? && !datadog_configuration[:dry_run_enabled]

              test_session = test_tracing_component.start_test_session(
                tags: {
                  CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                  CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s
                },
                service: datadog_configuration[:service_name],
                estimated_total_tests_count: ::RSpec.world.example_count
              )

              test_module = test_tracing_component.start_test_module(Ext::FRAMEWORK)

              result = super
              return result unless test_module && test_session
              # distributed test session must end in the parent process (for RSpec it would be parallel_tests CLI)
              return result if test_session.distributed

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

            def test_tracing_component
              Datadog.send(:components).test_tracing
            end

            def test_discovery_component
              Datadog.send(:components).test_discovery
            end

            def discover_tests(component)
              component.start

              examples = ::RSpec.world.all_examples

              examples.each do |example|
                next if example.metadata[:skip]

                component.record_test(
                  name: example.datadog_test_name,
                  suite: example.datadog_test_suite_name,
                  parameters: example.datadog_test_parameters,
                  module_name: Ext::FRAMEWORK,
                  source_file: example.datadog_test_suite_source_file_path
                )
              end

              component.finish
            end
          end
        end
      end
    end
  end
end
