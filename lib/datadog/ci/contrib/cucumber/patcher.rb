# frozen_string_literal: true

require "datadog/tracing/contrib/patcher"

require_relative "instrumentation"

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Patches 'cucumber' gem.
        module Patcher
          include Datadog::Tracing::Contrib::Patcher

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
