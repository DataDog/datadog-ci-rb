# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../instrumentation"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module Minitest
        module Runner
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          module ClassMethods
            def init_plugins(*args)
              super

              return unless datadog_configuration[:enabled]

              tests_count = ::Minitest::Runnable.runnables.sum { |runnable| runnable.runnable_methods.size }

              test_visibility_component.start_test_session(
                tags: {
                  CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                  CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s
                },
                service: datadog_configuration[:service_name],
                estimated_total_tests_count: tests_count,
                # if minitest is being used with a parallel runner, then tests split will happen by example, not by test suite
                # we need to always start/stop test suites in the parent process in this case
                local_test_suites_mode: false
              )
              test_visibility_component.start_test_module(Ext::FRAMEWORK)
            end

            def run_one_method(klass, method_name)
              return super unless datadog_configuration[:enabled]

              # @type var result: untyped
              result = nil

              test_retries_component.with_retries do
                result = super
              end

              # get the current test suite and mark this method as done, so we can check if all tests were executed
              # for this test suite
              test_suite_name = Helpers.test_suite_name(klass, method_name)
              test_suite = test_visibility_component.active_test_suite(test_suite_name)
              test_suite&.expected_test_done!(method_name)

              result
            end

            def run(*args)
              if datadog_configuration[:enabled] && test_discovery_component.enabled?
                ::Minitest.seed = 1
                discover_tests

                return true
              end
              super
            end

            private

            def datadog_integration
              CI::Contrib::Instrumentation.fetch_integration(:minitest)
            end

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end

            def test_visibility_component
              Datadog.send(:components).test_visibility
            end

            def test_retries_component
              Datadog.send(:components).test_retries
            end

            def test_discovery_component
              Datadog.send(:components).test_discovery
            end

            def discover_tests
              test_discovery_component.start

              ::Minitest::Runnable.runnables.each do |test_class|
                test_class.runnable_methods.each do |test_method|
                  test_suite_name = Helpers.test_suite_name(test_class, test_method)

                  source_path = Helpers.extract_source_location_from_class(test_class)&.first
                  source_path = Git::LocalRepository.relative_to_root(source_path) if source_path

                  test_discovery_component.record_test(
                    name: test_method,
                    suite: test_suite_name,
                    parameters: nil,
                    module_name: Ext::FRAMEWORK,
                    source_file: source_path
                  )
                end
              end

              test_discovery_component.finish
            end
          end
        end
      end
    end
  end
end
