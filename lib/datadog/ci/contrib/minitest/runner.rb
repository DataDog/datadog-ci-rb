# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module Minitest
        module Runner
          DD_ESTIMATED_TESTS_PER_SUITE = 5

          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          module ClassMethods
            def init_plugins(*args)
              super

              return unless datadog_configuration[:enabled]

              # minitest does not store the total number of tests, so we can't pass it to the test session
              # instead, we use the number of test suites * DD_ESTIMATED_TESTS_PER_SUITE as a rough estimate
              test_visibility_component.start_test_session(
                tags: {
                  CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                  CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Minitest::Integration.version.to_s
                },
                service: datadog_configuration[:service_name],
                total_tests_count: (DD_ESTIMATED_TESTS_PER_SUITE * ::Minitest::Runnable.runnables.size).to_i
              )
              test_visibility_component.start_test_module(Ext::FRAMEWORK)
            end

            def run_one_method(klass, method_name)
              return super unless datadog_configuration[:enabled]

              result = nil

              test_retries_component.with_retries do
                result = super
              end

              result
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end

            def test_visibility_component
              Datadog.send(:components).test_visibility
            end

            def test_retries_component
              Datadog.send(:components).test_retries
            end
          end
        end
      end
    end
  end
end
