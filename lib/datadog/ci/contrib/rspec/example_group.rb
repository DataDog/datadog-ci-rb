# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module RSpec
        # Instrument RSpec::Core::Example
        module ExampleGroup
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          # Instance methods for configuration
          module ClassMethods
            def run(reporter = ::RSpec::Core::NullReporter)
              return super unless configuration[:enabled]
              return super unless top_level?

              test_suite = Datadog::CI.start_test_suite(file_path)

              result = super

              if result
                test_suite.passed!
              else
                test_suite.failed!
              end
              test_suite.finish

              result
            end

            private

            def configuration
              Datadog.configuration.ci[:rspec]
            end
          end
        end
      end
    end
  end
end
