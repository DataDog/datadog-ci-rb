# frozen_string_literal: true

require_relative "../patcher"
require_relative "../rspec/runner"

module Datadog
  module CI
    module Contrib
      module Ciqueue
        # Patcher enables patching of 'rspec' module.
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            ::RSpec::Queue::Runner.include(Contrib::RSpec::Runner)
          end
        end
      end
    end
  end
end
