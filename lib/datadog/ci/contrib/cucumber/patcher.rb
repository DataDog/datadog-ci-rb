# frozen_string_literal: true

require_relative "../patcher"

require_relative "instrumentation"

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Patches 'cucumber' gem.
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::Cucumber::Runtime.include(Instrumentation)
          end
        end
      end
    end
  end
end
