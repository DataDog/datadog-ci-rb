# frozen_string_literal: true

require "datadog/core/telemetry/ext"

require_relative "../ext/settings"
require_relative "../git/tree_uploader"
require_relative "../test_optimisation/component"
require_relative "../test_optimisation/coverage/transport"
require_relative "../test_optimisation/coverage/writer"
require_relative "../test_visibility/component"
require_relative "../test_visibility/flush"
require_relative "../test_visibility/null_component"
require_relative "../test_visibility/serializers/factories/test_level"
require_relative "../test_visibility/serializers/factories/test_suite_level"
require_relative "../test_visibility/transport"
require_relative "../transport/adapters/telemetry_webmock_safe_adapter"
require_relative "../transport/api/builder"
require_relative "../transport/remote_settings_api"
require_relative "../utils/identity"
require_relative "../utils/parsing"
require_relative "../utils/test_run"
require_relative "../worker"

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to Datadog trace components
      module Components
        attr_reader :test_visibility, :test_optimisation

        def initialize(settings)
          @test_optimisation = nil
          @test_visibility = TestVisibility::NullComponent.new

          # Activate CI mode if enabled
          if settings.ci.enabled
            activate_ci!(settings)
          end

          super
        end

        def shutdown!(replacement = nil)
          super

          @test_visibility&.shutdown!
          @test_optimisation&.shutdown!
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
          configure_telemetry(settings)

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

          # @type ivar @test_optimisation: Datadog::CI::TestOptimisation::Component
          @test_optimisation = build_test_optimisation(settings, test_visibility_api)

          @test_visibility = TestVisibility::Component.new(
            test_optimisation: @test_optimisation,
            test_suite_level_visibility_enabled: !settings.ci.force_test_level_visibility,
            remote_settings_api: build_remote_settings_client(settings, test_visibility_api),
            git_tree_upload_worker: build_git_upload_worker(settings, test_visibility_api)
          )
        end

        def build_test_optimisation(settings, test_visibility_api)
          if settings.ci.itr_code_coverage_use_single_threaded_mode &&
              settings.ci.itr_test_impact_analysis_use_allocation_tracing
            Datadog.logger.warn(
              "Intelligent test runner: Single threaded coverage mode is incompatible with allocation tracing. " \
              "Allocation tracing will be disabled. It means that test impact analysis will not be able to detect " \
              "instantiations of objects in your code, which is important for ActiveRecord models. " \
              "Please add your app/model folder to the list of tracked files or disable single threaded coverage mode."
            )

            settings.ci.itr_test_impact_analysis_use_allocation_tracing = false
          end

          if RUBY_VERSION.start_with?("3.2.") && RUBY_VERSION < "3.2.3" &&
              settings.ci.itr_test_impact_analysis_use_allocation_tracing
            Datadog.logger.warn(
              "Intelligent test runner: Allocation tracing is not supported in Ruby versions 3.2.0, 3.2.1 and 3.2.2 and will be forcibly " \
              "disabled. This is due to a VM bug that can lead to crashes (https://bugs.ruby-lang.org/issues/19482). " \
              "Please update your Ruby version or add your app/model folder to the list of tracked files." \
              "Set env variable DD_CIVISIBILITY_ITR_TEST_IMPACT_ANALYSIS_USE_ALLOCATION_TRACING to 0 to disable this warning."
            )
            settings.ci.itr_test_impact_analysis_use_allocation_tracing = false
          end

          TestOptimisation::Component.new(
            api: test_visibility_api,
            dd_env: settings.env,
            config_tags: custom_configuration(settings),
            coverage_writer: build_coverage_writer(settings, test_visibility_api),
            enabled: settings.ci.enabled && settings.ci.itr_enabled,
            bundle_location: settings.ci.itr_code_coverage_excluded_bundle_path,
            use_single_threaded_coverage: settings.ci.itr_code_coverage_use_single_threaded_mode,
            use_allocation_tracing: settings.ci.itr_test_impact_analysis_use_allocation_tracing
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

          TestOptimisation::Coverage::Writer.new(
            transport: TestOptimisation::Coverage::Transport.new(api: api)
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

        def configure_telemetry(settings)
          # in development environment Datadog's telemetry is disabled by default
          # for test visibility we want to enable it by default unless explicitly disabled
          # NOTE: before agentless mode is released, we only enable telemetry when running with Datadog Agent
          env_telemetry_enabled = ENV[Core::Telemetry::Ext::ENV_ENABLED]
          settings.telemetry.enabled = !settings.ci.agentless_mode_enabled &&
            (env_telemetry_enabled.nil? || Utils::Parsing.convert_to_bool(env_telemetry_enabled))

          return unless settings.telemetry.enabled

          begin
            require "datadog/core/environment/identity"
            require "datadog/core/telemetry/http/adapters/net"

            # patch gem's identity to report datadog-ci library version instead of datadog gem version
            Core::Environment::Identity.include(CI::Utils::Identity)

            # patch gem's telemetry transport layer to use Net::HTTP instead of WebMock's Net::HTTP
            Core::Telemetry::Http::Adapters::Net.include(CI::Transport::Adapters::TelemetryWebmockSafeAdapter)
          rescue => e
            Datadog.logger.warn("Failed to patch Datadog gem's telemetry layer: #{e}")
          end

          # REMOVE BEFORE SUBMITTING FOR REVIEW
          # settings.telemetry.agentless_enabled = true
          # settings.telemetry.shutdown_timeout_seconds = 60
        end

        def timecop?
          Gem.loaded_specs.key?("timecop") || !!defined?(Timecop)
        end
      end
    end
  end
end
