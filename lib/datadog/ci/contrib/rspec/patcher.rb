# frozen_string_literal: true

require_relative "../patcher"

require_relative "example"
require_relative "example_group"
require_relative "runner"

module Datadog
  module CI
    module Contrib
      module RSpec
        # Patcher enables patching of 'rspec' module.
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            # ci-queue test runner instrumentation
            # https://github.com/Shopify/ci-queue
            if ci_queue?
              ::RSpec::Queue::Runner.include(Runner)
            end

            # default rspec test runner instrumentation
            ::RSpec::Core::Runner.include(Runner)

            ::RSpec::Core::Example.include(Example)
            ::RSpec::Core::ExampleGroup.include(ExampleGroup)
          end

          def ci_queue?
            !!defined?(::RSpec::Queue::Runner)
          end
        end
      end
    end
  end
end
