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
            include Helpers::RunnableClassMethods

            def run(*args)
              return super unless datadog_configuration[:enabled]
              return super if Helpers.parallel?(self)

              test_suite = Helpers.start_test_suite(self)
              if test_suite&.should_skip?
                return Helpers.skip_test_suite(test_suite)
              end

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
