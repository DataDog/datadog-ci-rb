# frozen_string_literal: true

require_relative "../flush"
require_relative "../test_visibility/transport"

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to Datadog trace components
      module Components
        def initialize(settings)
          # Activate CI mode if enabled
          activate_ci!(settings) if settings.ci.enabled

          # Initialize normally
          super
        end

        def activate_ci!(settings)
          agentless_transport = nil

          if settings.ci.agentless_mode_enabled
            if settings.api_key.nil?
              # agentless mode is requested but no API key is provided -
              # we cannot continue and log an error
              # Tests are running without CI visibility enabled

              Datadog.logger.error(
                "DATADOG CONFIGURATION - CI VISIBILITY - ATTENTION - " \
                "Agentless mode was enabled but DD_API_KEY is not set: CI visibility is disabled. " \
                "Please make sure to set valid api key in DD_API_KEY environment variable"
              )

              settings.ci.enabled = false
              return
            else
              agentless_transport = Datadog::CI::TestVisibility::Transport.new(api_key: settings.api_key)
            end
          end

          # Deactivate telemetry
          settings.telemetry.enabled = false

          # Deactivate remote configuration
          settings.remote.enabled = false

          # Activate underlying tracing test mode
          settings.tracing.test_mode.enabled = true

          # Choose user defined TraceFlush or default to CI TraceFlush
          settings.tracing.test_mode.trace_flush = settings.ci.trace_flush || CI::Flush::Finished.new

          writer_options = settings.ci.writer_options
          if agentless_transport
            writer_options[:transport] = agentless_transport
            writer_options[:shutdown_timeout] = 60

            settings.tracing.test_mode.async = true
          end

          settings.tracing.test_mode.writer_options = writer_options
        end
      end
    end
  end
end
