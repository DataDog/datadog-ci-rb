require_relative "helpers"

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
              return super if Helpers.parallel?(self)

              method = runnable_methods.first
              return super if method.nil?

              test_suite_name = Helpers.test_suite_name(self, method)

              test_suite = Datadog::CI.start_test_suite(test_suite_name)

              results = super
              return results unless test_suite

              test_suite.finish

              results
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end
          end
        end
      end
    end
  end
end
