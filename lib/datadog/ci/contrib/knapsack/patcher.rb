# frozen_string_literal: true

require_relative "../patcher"
require_relative "rspec_adapter"
require_relative "test_suite"

module Datadog
  module CI
    module Contrib
      module Knapsack
        module Patcher
          include Datadog::CI::Contrib::Patcher

          def self.patch
            ::KnapsackPro::Adapters::RSpecAdapter.include(Datadog::CI::Contrib::Knapsack::RSpecAdapter)
            ::KnapsackPro::TestSuite.include(Datadog::CI::Contrib::Knapsack::TestSuite)

            if ::RSpec::Core::Runner.ancestors.include?(::KnapsackPro::Extensions::RSpecExtension::Runner)
              # knapsack already patched rspec runner
              require_relative "runner"
              ::RSpec::Core::Runner.include(Datadog::CI::Contrib::Knapsack::Runner)
            else
              # knapsack didn't patch rspec runner yet
              require_relative "extension"
              ::KnapsackPro::Extensions::RSpecExtension.include(Datadog::CI::Contrib::Knapsack::Extension)
            end
          end
        end
      end
    end
  end
end
