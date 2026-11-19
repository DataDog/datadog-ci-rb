# frozen_string_literal: true

module Datadog
  module CI
    module Configuration
      # Tracer reconfiguration must not replace the independent CI runtime.
      module Reconfiguration
        def configure(&block)
          result = super
          CI.configuration_changed!
          result
        end
      end
    end
  end
end
