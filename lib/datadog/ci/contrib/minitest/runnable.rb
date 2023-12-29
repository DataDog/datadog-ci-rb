require_relative "suite"

module Datadog
  module CI
    module Contrib
      module Minitest
        module Runnable
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          module ClassMethods
            def run(*)
              return super unless datadog_configuration[:enabled]
              return super if parallel?
              return super if runnable_methods.empty?

              method = runnable_methods.first
              test_suite_name = Suite.name(self, method)

              test_suite = Datadog::CI.start_test_suite(test_suite_name)
              test_suite.passed! # will be overridden if any test fails

              results = super

              test_suite.finish

              results
            end

            private

            def parallel?
              test_order == :parallel
            end

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end
          end
        end
      end
    end
  end
end
