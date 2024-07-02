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
          @itr = nil
          @ci_recorder = TestVisibility::NullRecorder.new

          # Activate CI mode if enabled
          if settings.ci.enabled
            activate_ci!(settings)
          end

          super
        end

        def shutdown!(replacement = nil)
          super

          @ci_recorder&.shutdown!
          @itr&.shutdown!
        end

        def activate_ci!(settings)
          unless settings.tracing.enabled
            Datadog.logger.error(
              "CI visibility requires tracing to be enabled. Disabling CI visibility. " \
              "NOTE: if you didn't disable tracing intentionally, add `c.tracing.enabled = true` to " \
              "your Datadog.configure block."
            )
            settings.ci.enabled = false
            return
          end

          # Builds test visibility API layer in agentless or EvP proxy mode
          test_visibility_api = build_test_visibility_api(settings)
          # bail out early if api is misconfigured
          return unless settings.ci.enabled

          # Configure datadog gem for test visibility mode

          # Deactivate telemetry
          settings.telemetry.enabled = false

          # Test visibility uses its own remote settings
          settings.remote.enabled = false

          # startup logs are useless for test visibility and create noise
          settings.diagnostics.startup_logs.enabled = false

          # When timecop is present, Time.now is mocked and .now_without_mock_time is added on Time to
          # get the current time without the mock.
          if timecop?
            settings.time_now_provider = -> do
              Time.now_without_mock_time
            rescue NoMethodError
              # fallback to normal Time.now if Time.now_without_mock_time is not defined for any reason
              Time.now
            end
          end

          # Configure Datadog::Tracing module

          # No need not use 128-bit trace ids for test visibility,
          # they are used for OTEL compatibility in Datadog tracer
          settings.tracing.trace_id_128_bit_generation_enabled = false

          # Activate underlying tracing test mode with async worker
          settings.tracing.test_mode.enabled = true
          settings.tracing.test_mode.async = true
          settings.tracing.test_mode.trace_flush = settings.ci.trace_flush || CI::TestVisibility::Flush::Partial.new

          trace_writer_options = settings.ci.writer_options
          trace_writer_options[:shutdown_timeout] = 60
          trace_writer_options[:buffer_size] = 10_000
          tracing_transport = build_tracing_transport(settings, test_visibility_api)
          trace_writer_options[:transport] = tracing_transport if tracing_transport

          settings.tracing.test_mode.writer_options = trace_writer_options

          # @type ivar @itr: Datadog::CI::ITR::Runner
          @itr = ITR::Runner.new(
            api: test_visibility_api,
            dd_env: settings.env,
            config_tags: custom_configuration(settings),
            coverage_writer: build_coverage_writer(settings, test_visibility_api),
            enabled: settings.ci.enabled && settings.ci.itr_enabled,
            bundle_location: settings.ci.itr_code_coverage_excluded_bundle_path,
            use_single_threaded_coverage: settings.ci.itr_code_coverage_use_single_threaded_mode
          )

          # CI visibility recorder global instance
          @ci_recorder = TestVisibility::Recorder.new(
            test_suite_level_visibility_enabled: !settings.ci.force_test_level_visibility,
            itr: @itr,
            remote_settings_api: build_remote_settings_client(settings, test_visibility_api),
            git_tree_upload_worker: build_git_upload_worker(settings, test_visibility_api)
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

              # only legacy APM protocol is supported, so no test suite level visibility
              settings.ci.force_test_level_visibility = true

              # ITR is not supported with APM protocol
              settings.ci.itr_enabled = false
            end
          end

          api
        end

        def build_tracing_transport(settings, api)
          return nil if api.nil?

          TestVisibility::Transport.new(
            api: api,
            serializers_factory: serializers_factory(settings),
            dd_env: settings.env
          )
        end

        def build_coverage_writer(settings, api)
          return nil if api.nil?

          ITR::Coverage::Writer.new(
            transport: ITR::Coverage::Transport.new(api: api)
          )
        end

        def build_git_upload_worker(settings, api)
          if settings.ci.git_metadata_upload_enabled
            git_tree_uploader = Git::TreeUploader.new(api: api)
            Worker.new do |repository_url|
              git_tree_uploader.call(repository_url)
            end
          else
            DummyWorker.new
          end
        end

        def build_remote_settings_client(settings, api)
          Transport::RemoteSettingsApi.new(
            api: api,
            dd_env: settings.env,
            config_tags: custom_configuration(settings)
          )
        end

        # fetch custom tags provided by the user in DD_TAGS env var
        # with prefix test.configuration.
        def custom_configuration(settings)
          @custom_configuration ||= Utils::TestRun.custom_configuration(settings.tags)
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

        def timecop?
          Gem.loaded_specs.key?("timecop") || !!defined?(Timecop)
        end
      end
    end
  end
end
