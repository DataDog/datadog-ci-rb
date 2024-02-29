# frozen_string_literal: true

module Datadog
  module CI
    module ITR
      # Intelligent test runner implementation
      # Integrates with backend to provide test impact analysis data and
      # skip tests that are not impacted by the changes
      class Runner
        def initialize(
          enabled: false
        )
          @enabled = enabled
        end

        def enabled?
          @enabled
        end

        def configure
          return unless enabled?

          Datadog.logger.debug("Sending ITR settings request...")
        end
      end
    end
  end
end
