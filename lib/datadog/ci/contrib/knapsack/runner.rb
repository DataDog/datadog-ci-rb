# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../rspec/ext"
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

              # @type var test_session: Datadog::CI::TestSession?
              test_session = test_tracing_component.start_test_session(
                tags: {
                  CI::Ext::Test::TAG_FRAMEWORK => CI::Contrib::RSpec::Ext::FRAMEWORK,
                  CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s
                },
                service: datadog_configuration[:service_name]
              )

              # @type var test_module: Datadog::CI::TestModule?
              test_module = test_tracing_component.start_test_module(CI::Contrib::RSpec::Ext::FRAMEWORK)

              return super unless test_module && test_session

              result = nil
              begin
                result = super
              ensure
                [test_module, test_session].each do |span|
                  _dd_cleanup { (result == 0) ? span.passed! : span.failed! }
                end
                _dd_cleanup { test_module.finish }
                _dd_cleanup { test_session.finish }
              end
            end

            private

            def _dd_cleanup
              yield
            rescue => error
              Datadog.logger.warn("Knapsack cleanup failed: #{error.class}: #{error.message}")
            end

            def datadog_integration
              CI::Contrib::Instrumentation.fetch_integration(:rspec)
            end

            def datadog_configuration
              Datadog.configuration.ci[:rspec]
            end

            def test_tracing_component
              Datadog.send(:components).test_tracing
            end
          end
        end
      end
    end
  end
end
