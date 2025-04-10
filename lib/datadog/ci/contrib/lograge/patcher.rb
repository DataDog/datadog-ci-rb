# frozen_string_literal: true

require_relative "../patcher"

module Datadog
  module CI
    module Contrib
      module Lograge
        # Patcher enables patching of lograge module
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            # Logic to patch Lograge
            # Implement the actual patching mechanism here
            # Example implementation:
            # ::Lograge::RequestLogSubscriber.prepend(RequestLogSubscriberPatch)
            true
          end
        end
      end
    end
  end
end
