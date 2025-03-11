# frozen_string_literal: true

require_relative "integration"

module Datadog
  module CI
    module Contrib
      module ParallelTests
        # Patcher enables patching of parallel_tests module
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            # Empty implementation as requested
            # Will be filled in later
          end
        end
      end
    end
  end
end
