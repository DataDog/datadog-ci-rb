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

            if knapsack_pro?
              # Knapsack Pro test runner instrumentation
              # https://github.com/KnapsackPro/knapsack_pro-ruby
              require_relative "knapsack_pro/patcher"
              Datadog::CI::Contrib::RSpec::KnapsackPro::Patcher.patch
            end

            # default rspec test runner instrumentation
            ::RSpec::Core::Runner.include(Runner)

            ::RSpec::Core::Example.include(Example)
            ::RSpec::Core::ExampleGroup.include(ExampleGroup)
          end

          def ci_queue?
            !!defined?(::RSpec::Queue::Runner)
          end

          def knapsack_pro?
            knapsack_version = Gem.loaded_specs["knapsack_pro"]&.version

            # additional instrumentation is needed for KnapsackPro version 7 and later
            !!defined?(::KnapsackPro) &&
              !knapsack_version.nil? && knapsack_version >= Gem::Version.new("7")
          end
        end
      end
    end
  end
end
