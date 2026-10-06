# frozen_string_literal: true

module Datadog
  module CI
    module Configuration
      # Replacing components during a test session discards its context and remote settings.
      module Reconfiguration
        def configure(&block)
          current = components(allow_initialization: false)
          if current&.test_tracing&.configuration_locked?
            warn_about_ci_reconfiguration
            return configuration
          end

          super
        end

        private

        def warn_about_ci_reconfiguration
          logger.warn(
            "Datadog.configure ignored during an active Test Optimization session to preserve test context and remote settings. " \
            "Move Datadog.configure calls before the test session starts."
          )
        end
      end
    end
  end
end
