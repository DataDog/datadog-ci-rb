# frozen_string_literal: true

require "datadog/tracing/contrib/patcher"
require_relative "example"
require_relative "runner"

module Datadog
  module CI
    module Contrib
      module RSpec
        # Patcher enables patching of 'rspec' module.
        module Patcher
          include Datadog::Tracing::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::RSpec::Core::Example.include(Example)
            ::RSpec::Core::Runner.include(Runner)

            ::RSpec::Core::ExampleGroup.class_eval do
              class << self
                alias_method :__run, :run

                def run(reporter = ::RSpec::Core::NullReporter)
                  return __run(reporter) unless top_level?

                  test_suite = Datadog::CI.start_test_suite(file_path)
                  result = __run(reporter)
                  if result
                    test_suite.passed!
                  else
                    test_suite.failed!
                  end
                  test_suite.finish
                  result
                end
              end
            end
          end
        end
      end
    end
  end
end
