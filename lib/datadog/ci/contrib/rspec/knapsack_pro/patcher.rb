# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module RSpec
        module KnapsackPro
          module Patcher
            def self.patch
              if defined?(::KnapsackPro::Extensions::RSpecExtension::Runner) &&
                  ::RSpec::Core::Runner.ancestors.include?(::KnapsackPro::Extensions::RSpecExtension::Runner)
                # knapsack already patched rspec runner
                require_relative "runner"
                ::RSpec::Core::Runner.include(KnapsackPro::Runner)
              else
                # knapsack didn't patch rspec runner yet
                require_relative "extension"
                ::KnapsackPro::Extensions::RSpecExtension.include(KnapsackPro::Extension)
              end
            end
          end
        end
      end
    end
  end
end
