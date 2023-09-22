# frozen_string_literal: true

require_relative "../flush"

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
          writer_options = settings.ci.writer_options

          if settings.ci.agentless_mode_enabled
            if settings.api_key.nil?
              # agentless mode is requested but no API key is provided -
              # we cannot continue and log an error
              # Tests are running without CI visibility enabled

              Datadog.logger.error(
                "Agentless mode was enabled but DD_API_KEY is not set: CI visibility is disabled. " \
                "Please make sure to set valid api key in DD_API_KEY environment variable"
              )

              settings.ci.enabled = false
              return
            else
              agentless_transport = Datadog::CI::TestVisibility::Transport.new(api_key: settings.api_key)
            end
          end

          writer_options[:transport] = agentless_transport if agentless_transport

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

          # Pass through any other options
          settings.tracing.test_mode.writer_options = settings.ci.writer_options
        end
      end
    end
  end
end
