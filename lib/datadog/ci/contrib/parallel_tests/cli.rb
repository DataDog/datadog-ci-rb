# frozen_string_literal: true

require_relative "../../ext/test"

module Datadog
  module CI
    module Contrib
      module ParallelTests
        module CLI
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def run_tests_in_parallel(num_processes, options)
              return super if @runner != ::ParallelTests::RSpec::Runner

              begin
                # TODO: how to get rspec framework version? it's not loaded yet
                # TODO: how to get total tests count? RSpec isn't loaded yet so we cannot access ::RSpec.world.example_count
                test_session = test_visibility_component.start_test_session(
                  tags: {
                    CI::Ext::Test::TAG_FRAMEWORK => "rspec",
                    CI::Ext::Test::TAG_FRAMEWORK_VERSION => "0.0.0"

                  },
                  service: datadog_configuration[:service_name],
                  estimated_total_tests_count: 1000
                )

                super
              ensure
                test_session&.finish
              end
            end

            def any_test_failed?(test_results)
              res = super

              test_session = test_visibility_component.active_test_session
              if res
                test_session&.failed!
              else
                test_session&.passed!
              end

              res
            end

            def datadog_configuration
              Datadog.configuration.ci[:paralleltests]
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
