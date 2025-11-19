# frozen_string_literal: true

require "datadog/core/telemetry/ext"

require_relative "../ext/settings"
require_relative "../git/tree_uploader"
require_relative "../impacted_tests_detection/component"
require_relative "../impacted_tests_detection/null_component"
require_relative "../logs/component"
require_relative "../logs/transport"
require_relative "../remote/null_component"
require_relative "../remote/component"
require_relative "../remote/library_settings_client"
require_relative "../test_management/component"
require_relative "../test_management/null_component"
require_relative "../test_management/tests_properties"
require_relative "../test_optimisation/component"
require_relative "../test_optimisation/coverage/transport"
require_relative "../test_retries/component"
require_relative "../test_retries/null_component"
require_relative "../test_discovery/component"
require_relative "../test_discovery/null_component"
require_relative "../test_visibility/component"
require_relative "../test_visibility/flush"
require_relative "../test_visibility/known_tests"
require_relative "../test_visibility/null_component"
require_relative "../test_visibility/serializers/factories/test_level"
require_relative "../test_visibility/serializers/factories/test_suite_level"
require_relative "../test_visibility/null_transport"
require_relative "../test_visibility/transport"
require_relative "../transport/adapters/telemetry_webmock_safe_adapter"
require_relative "../transport/api/builder"
require_relative "../utils/parsing"
require_relative "../utils/test_run"
require_relative "../async_writer"
require_relative "../worker"

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to Datadog trace components
      module Components
        attr_reader :test_visibility, :test_optimisation, :git_tree_upload_worker, :ci_remote, :test_retries,
          :test_management, :agentless_logs_submission, :impacted_tests_detection, :test_discovery

        def initialize(settings)
          @test_optimisation = nil
          @test_visibility = TestVisibility::NullComponent.new
          @git_tree_upload_worker = DummyWorker.new
          @ci_remote = Remote::NullComponent.new
          @test_retries = TestRetries::NullComponent.new
          @test_management = TestManagement::NullComponent.new
          @impacted_tests_detection = ImpactedTestsDetection::NullComponent.new
          @test_discovery = TestDiscovery::NullComponent.new

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
          @agentless_logs_submission&.shutdown!
          @test_discovery&.shutdown!
          @git_tree_upload_worker&.stop
        end

        def activate_ci!(settings)
          unless settings.tracing.enabled
            Datadog.logger.error(
              "Test Optimization requires tracing to be enabled. Disabling Test Optimization. " \
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

          # timecop configuration
          configure_time_providers(settings)

          # first check if we are in test discovery mode and configure library accordingly
          # @type ivar @test_discovery: Datadog::CI::TestDiscovery::Component
          @test_discovery = TestDiscovery::Component.new(
            enabled: settings.ci.test_discovery_enabled,
            output_path: settings.ci.test_discovery_output_path
          )
          @test_discovery.disable_features_for_test_discovery!(settings)

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

          @git_tree_upload_worker = build_git_upload_worker(settings, test_visibility_api)
          @ci_remote = Remote::Component.new(
            library_settings_client: build_library_settings_client(settings, test_visibility_api),
            test_discovery_enabled: settings.ci.test_discovery_enabled
          )
          @test_retries = TestRetries::Component.new(
            retry_failed_tests_enabled: settings.ci.retry_failed_tests_enabled,
            retry_failed_tests_max_attempts: settings.ci.retry_failed_tests_max_attempts,
            retry_failed_tests_total_limit: settings.ci.retry_failed_tests_total_limit,
            retry_new_tests_enabled: settings.ci.retry_new_tests_enabled,
            retry_flaky_fixed_tests_enabled: settings.ci.test_management_enabled,
            retry_flaky_fixed_tests_max_attempts: settings.ci.test_management_attempt_to_fix_retries_count
          )

          @test_management = TestManagement::Component.new(
            enabled: settings.ci.test_management_enabled,
            tests_properties_client: TestManagement::TestsProperties.new(api: test_visibility_api)
          )

          # @type ivar @test_optimisation: Datadog::CI::TestOptimisation::Component
          @test_optimisation = build_test_optimisation(settings, test_visibility_api)
          @test_visibility = TestVisibility::Component.new(
            test_suite_level_visibility_enabled: !settings.ci.force_test_level_visibility,
            logical_test_session_name: settings.ci.test_session_name,
            known_tests_client: build_known_tests_client(settings, test_visibility_api),
            context_service_uri: settings.ci.test_visibility_drb_server_uri
          )

          @agentless_logs_submission = build_agentless_logs_component(settings, test_visibility_api)

          @impacted_tests_detection = ImpactedTestsDetection::Component.new(enabled: settings.ci.impacted_tests_detection_enabled)
        end

        def build_test_optimisation(settings, test_visibility_api)
          if settings.ci.itr_code_coverage_use_single_threaded_mode &&
              settings.ci.itr_test_impact_analysis_use_allocation_tracing
            Datadog.logger.warn(
              "Test Impact Analysis: Single threaded coverage mode is incompatible with allocation tracing. " \
              "Allocation tracing will be disabled. It means that test impact analysis will not be able to detect " \
              "instantiations of objects in your code, which is important for ActiveRecord models. " \
              "Please add your app/model folder to the list of tracked files or disable single threaded coverage mode."
            )

            settings.ci.itr_test_impact_analysis_use_allocation_tracing = false
          end

          if RUBY_VERSION.start_with?("3.2.") && RUBY_VERSION < "3.2.3" &&
              settings.ci.itr_test_impact_analysis_use_allocation_tracing
            Datadog.logger.warn(
              "Test Impact Analysis: Allocation tracing is not supported in Ruby versions 3.2.0, 3.2.1 and 3.2.2 and will be forcibly " \
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

            Datadog.logger.debug("Test Optimization configured to use agentless transport")

            api = Transport::Api::Builder.build_agentless_api(settings)
            if api.nil?
              Datadog.logger.error do
                "DATADOG CONFIGURATION - TEST OPTIMIZATION - ATTENTION - " \
                "Agentless mode was enabled but DD_API_KEY is not set: Test Optimization is disabled. " \
                "Please make sure to set valid api key in DD_API_KEY environment variable"
              end

              # Tests are running without Test Optimization enabled
              settings.ci.enabled = false
            end
          else
            Datadog.logger.debug("Test Optimization configured to use agent transport via EVP proxy")

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
          # NullTransport ignores traces
          return TestVisibility::NullTransport.new if settings.ci.discard_traces
          # nil means that default legacy APM transport will be used (only for very old Datadog Agent versions)
          return nil if api.nil?

          TestVisibility::Transport.new(
            api: api,
            serializers_factory: serializers_factory(settings),
            dd_env: settings.env
          )
        end

        def build_coverage_writer(settings, api)
          # nil means that coverage event will be ignored
          return nil if api.nil? || settings.ci.discard_traces

          AsyncWriter.new(
            transport: TestOptimisation::Coverage::Transport.new(api: api)
          )
        end

        def build_git_upload_worker(settings, api)
          if settings.ci.git_metadata_upload_enabled
            git_tree_uploader = Git::TreeUploader.new(api: api, force_unshallow: settings.ci.impacted_tests_detection_enabled)
            Worker.new do |repository_url|
              git_tree_uploader.call(repository_url)
            end
          else
            DummyWorker.new
          end
        end

        def build_library_settings_client(settings, api)
          Remote::LibrarySettingsClient.new(
            api: api,
            dd_env: settings.env,
            config_tags: custom_configuration(settings)
          )
        end

        def build_known_tests_client(settings, api)
          TestVisibility::KnownTests.new(
            api: api,
            dd_env: settings.env,
            config_tags: custom_configuration(settings)
          )
        end

        def build_agentless_logs_component(settings, api)
          if settings.ci.agentless_logs_submission_enabled && !settings.ci.agentless_mode_enabled
            Datadog.logger.warn(
              "Agentless logs submission is enabled but agentless mode is not enabled. " \
              "Logs will not be submitted. " \
              "Please make sure to set DD_CIVISIBILITY_AGENTLESS_ENABLED to true if you want to submit logs in agentless mode. " \
              "Otherwise, set DD_AGENTLESS_LOG_SUBMISSION_ENABLED to 0 and use Datadog Agent to submit logs."
            )
            settings.ci.agentless_logs_submission_enabled = false
          end

          Logs::Component.new(
            enabled: settings.ci.agentless_logs_submission_enabled,
            writer: build_logs_writer(settings, api)
          )
        end

        def build_logs_writer(settings, api)
          return nil if api.nil? || settings.ci.discard_traces

          AsyncWriter.new(transport: Logs::Transport.new(api: api), options: {buffer_size: 1024})
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
            "TEST OPTIMIZATION CONFIGURATION " \
            "Agentless mode was enabled but DD_SITE is not set to one of the following: #{Ext::Settings::DD_SITE_ALLOWLIST.join(", ")}. " \
            "Please make sure to set valid site in DD_SITE environment variable"
          end
        end

        def configure_telemetry(settings)
          # in development environment Datadog's telemetry is disabled by default
          # for test visibility we want to enable it by default unless explicitly disabled
          # NOTE: before agentless mode is released, we only enable telemetry when running with Datadog Agent
          env_telemetry_enabled = ENV[Core::Telemetry::Ext::ENV_ENABLED]
          settings.telemetry.enabled = env_telemetry_enabled.nil? || Utils::Parsing.convert_to_bool(env_telemetry_enabled)

          return unless settings.telemetry.enabled

          settings.telemetry.agentless_enabled = true if settings.ci.agentless_mode_enabled
          settings.telemetry.shutdown_timeout_seconds = 60.0

          begin
            require "datadog/core/transport/http/adapters/net"

            # patch gem's core transport layer to use Net::HTTP instead of WebMock's Net::HTTP
            Core::Transport::HTTP::Adapters::Net.include(CI::Transport::Adapters::TelemetryWebmockSafeAdapter)
          rescue LoadError, StandardError => e
            Datadog.logger.warn("Failed to patch Datadog gem's telemetry layer: #{e}")
          end

          # for compatibility with old telemetry transport
          begin
            require "datadog/core/telemetry/http/adapters/net"
            Core::Telemetry::Http::Adapters::Net.include(CI::Transport::Adapters::TelemetryWebmockSafeAdapter)
          rescue LoadError, StandardError => e
            Datadog.logger.debug("The old telemetry transport layer is not available: #{e}")
          end
        end

        # When timecop is present:
        # - Time.now is mocked and .now_without_mock_time is added on Time to get the current time without the mock.
        # - Process.clock_gettime is mocked and .clock_gettime_without_mock is added on Process to get the monotonic time without the mock.
        def configure_time_providers(settings)
          return unless timecop?

          settings.time_now_provider = -> do
            Time.now_without_mock_time
          rescue NoMethodError
            # fallback to normal Time.now if Time.now_without_mock_time is not defined for any reason
            Time.now
          end

          if defined?(Process.clock_gettime_without_mock)
            settings.get_time_provider = ->(unit = :float_second) do
              ::Process.clock_gettime_without_mock(::Process::CLOCK_MONOTONIC, unit)
            rescue NoMethodError
              # fallback to normal Process.clock_gettime if Process.clock_gettime_without_mock is not defined for any reason
              Process.clock_gettime(::Process::CLOCK_MONOTONIC, unit)
            end
          end
        end

        def timecop?
          Gem.loaded_specs.key?("timecop") || !!defined?(Timecop)
        end
      end
    end
  end
end
