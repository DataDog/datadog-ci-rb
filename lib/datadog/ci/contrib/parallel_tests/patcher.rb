# frozen_string_literal: true

require_relative "cli"
require_relative "../patcher"

module Datadog
  module CI
    module Contrib
      module ParallelTests
        # Patcher enables patching of parallel_tests module
        module Patcher
          include Datadog::CI::Contrib::Patcher

          def self.patch
            ::ParallelTests::CLI.include(CLI)
          end
        end
      end
    end
  end
end
