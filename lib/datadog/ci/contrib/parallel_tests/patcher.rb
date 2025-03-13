# frozen_string_literal: true

require_relative "cli"
require_relative "integration"
require_relative "runner"
require_relative "../patcher"

module Datadog
  module CI
    module Contrib
      module ParallelTests
        # Patcher enables patching of parallel_tests module
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            ::ParallelTests::CLI.include(CLI)
          end
        end
      end
    end
  end
end
