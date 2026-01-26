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
              reporter.record ::Minitest.run_one_method(klass, method_name)
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end

            def _dd_test_tracing_component
              Datadog.send(:components).test_tracing
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
