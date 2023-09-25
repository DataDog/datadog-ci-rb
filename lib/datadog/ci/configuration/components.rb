# frozen_string_literal: true

require_relative "../flush"
require_relative "../writer"

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
          agentless_writer = nil

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
              agentless_writer = Datadog::CI::Writer.new(api_key: settings.api_key)
            end
          end

          # Deactivate telemetry
          settings.telemetry.enabled = false

          # Deactivate remote configuration
          settings.remote.enabled = false

          # enable tracing
          settings.tracing.enabled = true

          # Activate underlying tracing test mode
          settings.tracing.test_mode.enabled = true

          # Choose user defined TraceFlush or default to CI TraceFlush
          settings.tracing.test_mode.trace_flush = settings.ci.trace_flush \
                                             || CI::Flush::Finished.new

          # # Pass through any other options
          # settings.tracing.test_mode.writer_options = writer_options
          # Use agentless writer
          settings.tracing.writer = agentless_writer if agentless_writer
        end
      end
    end
  end
end
