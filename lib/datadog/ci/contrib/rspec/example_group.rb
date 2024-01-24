# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module RSpec
        # Instrument RSpec::Core::ExampleGroup
        module ExampleGroup
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          # Instance methods for configuration
          module ClassMethods
            def run(reporter = ::RSpec::Core::NullReporter)
              return super unless datadog_configuration[:enabled]
              return super unless top_level?

              suite_name = "#{description} at #{file_path}"
              test_suite = Datadog::CI.start_test_suite(suite_name)

              success = super
              return success unless test_suite

              test_suite.finish

              success
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:rspec]
            end
          end
        end
      end
    end
  end
end
