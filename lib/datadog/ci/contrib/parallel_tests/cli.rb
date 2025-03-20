# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../rspec/ext"

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
              # only rspec runner is supported for now
              return super if @runner != ::ParallelTests::RSpec::Runner

              begin
                test_session = test_visibility_component.start_test_session(
                  tags: {
                    CI::Ext::Test::TAG_FRAMEWORK => CI::Contrib::RSpec::Ext::FRAMEWORK,
                    CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_extract_rspec_version
                  },
                  service: datadog_configuration[:service_name],
                  estimated_total_tests_count: 10_000, # temporary value, updated by child processes
                  distributed: true
                )
                test_module = test_visibility_component.start_test_module("rspec")

                options[:env] ||= {}
                options[:env][CI::Ext::Settings::ENV_TEST_VISIBILITY_DRB_SERVER_URI] = test_visibility_component.context_service_uri

                super
              ensure
                test_module&.finish
                test_session&.finish
              end
            end

            def any_test_failed?(test_results)
              res = super

              test_session = test_visibility_component.active_test_session
              test_module = test_visibility_component.active_test_module
              if res
                test_module&.failed!
                test_session&.failed!
              else
                test_module&.passed!
                test_session&.passed!
              end

              res
            end

            def datadog_extract_rspec_version
              # Try to find either 'rspec' or 'rspec-core' gem
              if Gem.loaded_specs["rspec"]
                Gem.loaded_specs["rspec"].version.to_s
              elsif Gem.loaded_specs["rspec-core"]
                Gem.loaded_specs["rspec-core"].version.to_s
              else
                "0.0.0"
              end
            rescue => e
              Datadog.logger.debug("Error extracting RSpec version: #{e.class.name} - #{e.message}")
              "0.0.0"
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
