# frozen_string_literal: true

require_relative "../ext/settings"
require_relative "../itr/runner"
require_relative "../test_visibility/flush"
require_relative "../test_visibility/recorder"
require_relative "../test_visibility/null_recorder"
require_relative "../test_visibility/serializers/factories/test_level"
require_relative "../test_visibility/serializers/factories/test_suite_level"
require_relative "../test_visibility/transport"
require_relative "../transport/api/builder"

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to Datadog trace components
      module Components
        attr_reader :ci_recorder

        def initialize(settings)
          # Activate CI mode if enabled
          if settings.ci.enabled
            activate_ci!(settings)
          else
            @ci_recorder = TestVisibility::NullRecorder.new
          end

          super
        end

        def activate_ci!(settings)
          # Configure ddtrace library for CI visibility mode
          # Deactivate telemetry
          settings.telemetry.enabled = false

          # Deactivate remote configuration
          settings.remote.enabled = false

          # do not use 128-bit trace ids for CI visibility
          # they are used for OTEL compatibility in Datadog tracer
          settings.tracing.trace_id_128_bit_generation_enabled = false

          # Activate underlying tracing test mode
          settings.tracing.test_mode.enabled = true

          # Choose user defined TraceFlush or default to CI TraceFlush
          settings.tracing.test_mode.trace_flush = settings.ci.trace_flush || CI::TestVisibility::Flush::Partial.new

          # transport creation
          writer_options = settings.ci.writer_options
          test_visibility_api = build_test_visibility_api(settings)

          if test_visibility_api
            writer_options[:transport] = Datadog::CI::TestVisibility::Transport.new(
              api: test_visibility_api,
              serializers_factory: serializers_factory(settings),
              dd_env: settings.env
            )
            writer_options[:shutdown_timeout] = 60
            writer_options[:buffer_size] = 10_000

            settings.tracing.test_mode.async = true
          else
            # only legacy APM protocol is supported, so no test suite level visibility
            settings.ci.force_test_level_visibility = true

            # ITR is not supported with APM protocol
            settings.ci.itr_enabled = false
          end

          settings.tracing.test_mode.writer_options = writer_options

          itr = Datadog::CI::ITR::Runner.new(
            enabled: settings.ci.enabled && settings.ci.itr_enabled,
            api: test_visibility_api
          )

          # CI visibility recorder global instance
          @ci_recorder = TestVisibility::Recorder.new(
            test_suite_level_visibility_enabled: !settings.ci.force_test_level_visibility,
            itr: itr
          )
        end

        def build_test_visibility_api(settings)
          if settings.ci.agentless_mode_enabled
            check_dd_site(settings)

            Datadog.logger.debug("CI visibility configured to use agentless transport")

            api = Transport::Api::Builder.build_agentless_api(settings)
            if api.nil?
              Datadog.logger.error do
                "DATADOG CONFIGURATION - CI VISIBILITY - ATTENTION - " \
                "Agentless mode was enabled but DD_API_KEY is not set: CI visibility is disabled. " \
                "Please make sure to set valid api key in DD_API_KEY environment variable"
              end

              # Tests are running without CI visibility enabled
              settings.ci.enabled = false
            end

          else
            Datadog.logger.debug("CI visibility configured to use agent transport via EVP proxy")

            api = Transport::Api::Builder.build_evp_proxy_api(settings)
            if api.nil?
              Datadog.logger.debug(
                "Old agent version detected, no evp_proxy support. Forcing test level visibility mode"
              )
            end
          end

          api
        end

        def serializers_factory(settings)
          if settings.ci.force_test_level_visibility
            Datadog::CI::TestVisibility::Serializers::Factories::TestLevel
          else
            Datadog::CI::TestVisibility::Serializers::Factories::TestSuiteLevel
          end
        end

        def check_dd_site(settings)
          return if settings.site.nil?
          return if Ext::Settings::DD_SITE_ALLOWLIST.include?(settings.site)

          Datadog.logger.warn do
            "CI VISIBILITY CONFIGURATION " \
            "Agentless mode was enabled but DD_SITE is not set to one of the following: #{Ext::Settings::DD_SITE_ALLOWLIST.join(", ")}. " \
            "Please make sure to set valid site in DD_SITE environment variable"
          end
        end
      end
    end
  end
end
