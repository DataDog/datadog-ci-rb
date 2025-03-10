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
            def run(*args)
              return super unless datadog_configuration[:enabled]
              return super if Helpers.parallel?(self)

              test_suite = Helpers.start_test_suite(self)

              results = super
              return results unless test_suite

              test_suite.finish

              results
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
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
