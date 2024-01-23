# frozen_string_literal: true

require "datadog/tracing/contrib/patcher"

require_relative "example"
require_relative "example_group"
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
            if ci_queue?
              ::RSpec::Queue::Runner.include(Runner)
            end

            ::RSpec::Core::Runner.include(Runner)
            ::RSpec::Core::Example.include(Example)
            ::RSpec::Core::ExampleGroup.include(ExampleGroup)
          end

          def ci_queue?
            # ::RSpec::Queue::Runner is a ci-queue runner
            defined?(::RSpec::Queue::Runner)
          end
        end
      end
    end
  end
end
