# frozen_string_literal: true

module Datadog
  module CI
    module Configuration
      # Keeps existing CI configuration calls available without the optional tracer.
      module Fallback
        def configuration
          CI.configuration
        end

        def configure(&block)
          CI.configure(&block)
        end
      end
    end
  end
end
