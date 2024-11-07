# frozen_string_literal: true

require "knapsack_pro/extensions/rspec_extension"

require_relative "runner"

module Datadog
  module CI
    module Contrib
      module Knapsack
        module Extension
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          module ClassMethods
            def setup!
              super

              ::RSpec::Core::Runner.include(Datadog::CI::Contrib::Knapsack::Runner)
            end
          end
        end
      end
    end
  end
end
