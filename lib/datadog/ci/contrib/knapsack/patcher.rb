# frozen_string_literal: true

require_relative "../patcher"

module Datadog
  module CI
    module Contrib
      module Knapsack
        module Patcher
          include Datadog::CI::Contrib::Patcher

          def self.patch
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
