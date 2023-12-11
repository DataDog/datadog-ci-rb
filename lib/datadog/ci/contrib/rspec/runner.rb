# frozen_string_literal: true

require_relative "../../ext/test"
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
            def run_specs(example_groups)
              return super unless configuration[:enabled]

              test_session = CI.start_test_session(
                tags: {
                  CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                  CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::RSpec::Integration.version.to_s,
                  CI::Ext::Test::TAG_TYPE => CI::Ext::Test::TEST_TYPE
                },
                service: configuration[:service_name]
              )

              test_module = CI.start_test_module(Ext::TEST_MODULE_NAME)

              result = super

              if result != 0
                # TODO: repeating this twice feels clunky, we need to remove test_module API before GA
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

            def configuration
              Datadog.configuration.ci[:rspec]
            end
          end
        end
      end
    end
  end
end
