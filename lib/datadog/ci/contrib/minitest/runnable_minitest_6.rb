require_relative "helpers"

module Datadog
  module CI
    module Contrib
      module Minitest
        module RunnableMinitest6
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          module ClassMethods
            def run_suite(*args)
              return super unless datadog_configuration[:enabled]
              return super if Helpers.parallel?(self)

              test_suite = Helpers.start_test_suite(self)

              results = super
              return results unless test_suite

              test_suite.finish
              results
            end

            def run(klass, method_name, reporter)
              reporter.prerecord klass, method_name
              reporter.record dd_run_with_retries(klass, method_name)
            end

            def dd_run_with_retries(klass, method_name)
              return klass.new(method_name).run unless datadog_configuration[:enabled]

              # @type var result: untyped
              result = nil

              _dd_test_retries_component.with_retries do
                result = klass.new(method_name).run
              end

              # get the current test suite and mark this method as done, so we can check if all tests were executed
              # for this test suite
              test_suite_name = Helpers.test_suite_name(klass, method_name)
              test_suite = _dd_test_visibility_component.active_test_suite(test_suite_name)
              test_suite&.expected_test_done!(method_name)

              result
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end

            def _dd_test_visibility_component
              Datadog.send(:components).test_visibility
            end

            def _dd_test_retries_component
              Datadog.send(:components).test_retries
            end
          end
        end
      end
    end
  end
end
