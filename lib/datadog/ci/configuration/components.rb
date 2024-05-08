# frozen_string_literal: true

require_relative "../ext/settings"
require_relative "../git/tree_uploader"
require_relative "../itr/runner"
require_relative "../itr/coverage/transport"
require_relative "../itr/coverage/writer"
require_relative "../test_visibility/flush"
require_relative "../test_visibility/recorder"
require_relative "../test_visibility/null_recorder"
require_relative "../test_visibility/serializers/factories/test_level"
require_relative "../test_visibility/serializers/factories/test_suite_level"
require_relative "../test_visibility/transport"
require_relative "../transport/api/builder"
require_relative "../transport/remote_settings_api"
require_relative "../utils/test_run"
require_relative "../worker"

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to Datadog trace components
      module Components
        attr_reader :ci_recorder, :itr

        def initialize(settings)
          # Activate CI mode if enabled
          if settings.ci.enabled
            activate_ci!(settings)
          else
            @itr = nil
            @ci_recorder = TestVisibility::NullRecorder.new
          end

          super
        end

        def shutdown!(replacement = nil)
          super

          @ci_recorder&.shutdown!
          @itr&.shutdown!
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

          # startup logs are useless for CI visibility and create noise
          settings.diagnostics.startup_logs.enabled = false

          # transport creation
          writer_options = settings.ci.writer_options
          coverage_writer = nil
          test_visibility_api = build_test_visibility_api(settings)

          if test_visibility_api
            # setup writer for code coverage payloads
            coverage_writer = ITR::Coverage::Writer.new(
              transport: ITR::Coverage::Transport.new(api: test_visibility_api)
            )

            # configure tracing writer to send traces to CI visibility backend
            writer_options[:transport] = TestVisibility::Transport.new(
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

          custom_configuration_tags = Utils::TestRun.custom_configuration(settings.tags)

          remote_settings_api = Transport::RemoteSettingsApi.new(
            api: test_visibility_api,
            dd_env: settings.env,
            config_tags: custom_configuration_tags
          )

          itr = ITR::Runner.new(
            api: test_visibility_api,
            dd_env: settings.env,
            config_tags: custom_configuration_tags,
            coverage_writer: coverage_writer,
            enabled: settings.ci.enabled && settings.ci.itr_enabled,
            bundle_location: settings.ci.itr_code_coverage_excluded_bundle_path
          )

          git_tree_uploader = Git::TreeUploader.new(api: test_visibility_api)
          git_tree_upload_worker = if settings.ci.git_metadata_upload_enabled
            Worker.new do |repository_url|
              git_tree_uploader.call(repository_url)
            end
          else
            DummyWorker.new
          end

          # CI visibility recorder global instance
          @ci_recorder = TestVisibility::Recorder.new(
            test_suite_level_visibility_enabled: !settings.ci.force_test_level_visibility,
            itr: itr,
            remote_settings_api: remote_settings_api,
            git_tree_upload_worker: git_tree_upload_worker
          )

          @itr = itr
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
            TestVisibility::Serializers::Factories::TestLevel
          else
            TestVisibility::Serializers::Factories::TestSuiteLevel
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
