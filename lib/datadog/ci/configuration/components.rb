# frozen_string_literal: true

require_relative "settings"
require_relative "../event_tracer"
require_relative "../event_writer"
require_relative "../telemetry/component"
require_relative "../telemetry/null_component"
require_relative "../tracer_bridge/component"
require_relative "../tracer_bridge/null_component"
require_relative "../utils/identity"
require_relative "../ext/settings"
require_relative "../code_coverage/component"
require_relative "../code_coverage/null_component"
require_relative "../git/tree_uploader"
require_relative "../impacted_tests_detection/component"
require_relative "../impacted_tests_detection/null_component"
require_relative "../logs/component"
require_relative "../remote/null_component"
require_relative "../remote/component"
require_relative "../test_management/component"
require_relative "../test_management/null_component"
require_relative "../test_optimization_cache/component"
require_relative "../test_optimization_cache/null_component"
require_relative "../test_impact_analysis/null_component"
require_relative "../test_impact_analysis/component"
require_relative "../test_retries/component"
require_relative "../test_retries/null_component"
require_relative "../test_discovery/component"
require_relative "../test_discovery/null_component"
require_relative "../test_tracing/component"
require_relative "../test_tracing/null_component"
require_relative "../transport/api/builder"
require_relative "../utils/parsing"
require_relative "../utils/runtime_tags_overrides"
require_relative "../utils/test_run"
require_relative "../worker"

module Datadog
  module CI
    module Configuration
      # Builds and owns the CI runtime independently of tracer components.
      class Components
        attr_reader :test_tracing, :test_impact_analysis, :git_tree_upload_worker, :ci_remote, :test_retries,
          :test_management, :agentless_logs_submission, :impacted_tests_detection, :test_discovery, :code_coverage,
          :test_optimization_cache, :tracer, :tracer_bridge, :telemetry

        def initialize(settings)
          @test_impact_analysis = TestImpactAnalysis::NullComponent.new
          @test_tracing = TestTracing::NullComponent.new
          @git_tree_upload_worker = DummyWorker.new
          @ci_remote = Remote::NullComponent.new
          @test_retries = TestRetries::NullComponent.new
          @test_management = TestManagement::NullComponent.new
          @impacted_tests_detection = ImpactedTestsDetection::NullComponent.new
          @test_discovery = TestDiscovery::NullComponent.new
          @code_coverage = CodeCoverage::NullComponent.new
          @test_optimization_cache = TestOptimizationCache::NullComponent.new

          @telemetry = Telemetry::NullComponent.new
          @tracer_bridge = TracerBridge::NullComponent.new
          @tracer = EventTracer.new(
            writer: EventWriter.new(
              transport: TestTracing::Component.build_transport(api: nil, discard_traces: true, dd_env: settings.env),
              logger: CI.logger
            ),
            service: settings.service,
            tags: event_tags(settings.tags, settings.env, settings.version)
          )

          # Activate CI mode if enabled
          if settings.ci.enabled
            activate_ci!(settings)
          end
        end

        def shutdown!(replacement = nil)
          return if @shutdown
          @shutdown = true
          shutdown_component("test cache") { @test_optimization_cache&.shutdown! }
          shutdown_component("test tracing") { @test_tracing&.shutdown! }
          shutdown_component("test impact analysis") { @test_impact_analysis&.shutdown! }
          shutdown_component("logs") { @agentless_logs_submission&.shutdown! }
          shutdown_component("test discovery") { @test_discovery&.shutdown! }
          shutdown_component("code coverage") { @code_coverage&.shutdown! }
          shutdown_component("Git upload worker") { @git_tree_upload_worker&.stop }
          shutdown_component("tracer bridge") { @tracer_bridge.shutdown! }
          shutdown_component("event writer") { @tracer.shutdown! }
          shutdown_component("telemetry") { @telemetry.shutdown! }
        end

        def activate_ci!(settings)
          # Builds test visibility API layer in agentless or EvP proxy mode
          test_visibility_api = build_test_visibility_api(settings)
          # bail out early if api is misconfigured
          return unless settings.ci.enabled && test_visibility_api

          # Configure CI telemetry
          configure_telemetry(settings)

          # timecop configuration
          configure_time_providers(settings)

          # first check if we are in test discovery mode and configure library accordingly
          # @type ivar @test_discovery: Datadog::CI::TestDiscovery::Component
          @test_discovery = TestDiscovery::Component.new(
            enabled: settings.ci.test_discovery_enabled,
            output_path: settings.ci.test_discovery_output_path,
            minitest_plugin_autoload_enabled: settings.ci.minitest_no_plugins.nil?
          )
          @test_discovery.disable_features_for_test_discovery!(settings)

          @test_optimization_cache = TestOptimizationCache::Component.new(
            manifest_file: settings.ci.test_optimization_cache_manifest_file,
            runfiles_dir: settings.ci.test_optimization_cache_runfiles_dir,
            runfiles_manifest_file: settings.ci.test_optimization_cache_runfiles_manifest_file,
            test_srcdir: settings.ci.test_optimization_cache_test_srcdir
          )

          tracing_transport = TestTracing::Component.build_transport(
            api: test_visibility_api,
            discard_traces: settings.ci.discard_traces,
            dd_env: settings.env
          )
          writer_options = settings.ci.writer_options
          writer = EventWriter.new(
            transport: tracing_transport,
            logger: CI.logger,
            buffer_size: writer_options.fetch(:buffer_size, 10_000),
            flush_interval: writer_options.fetch(:flush_interval, writer_options.fetch(:interval, 1.0)),
            shutdown_timeout: writer_options.fetch(:shutdown_timeout, 60)
          )
          @tracer = EventTracer.new(writer: writer, service: settings.service, tags: event_tags(settings.tags, settings.env, settings.version))
          @tracer_bridge = if settings.ci.apm_spans_enabled
            TracerBridge::Component.new(writer: writer, logger: CI.logger)
          else
            TracerBridge::NullComponent.new
          end

          @git_tree_upload_worker = build_git_upload_worker(settings, test_visibility_api)
          @ci_remote = Remote::Component.build(
            api: test_visibility_api,
            dd_env: settings.env,
            test_skipping_mode: settings.ci.tia_test_skipping_mode,
            config_tags: custom_configuration(settings),
            test_discovery_enabled: settings.ci.test_discovery_enabled
          )
          @test_retries = TestRetries::Component.new(
            retry_failed_tests_enabled: settings.ci.retry_failed_tests_enabled,
            retry_failed_tests_max_attempts: settings.ci.retry_failed_tests_max_attempts,
            retry_failed_tests_total_limit: settings.ci.retry_failed_tests_total_limit,
            retry_new_tests_enabled: settings.ci.retry_new_tests_enabled,
            retry_flaky_fixed_tests_enabled: settings.ci.test_management_enabled,
            retry_flaky_fixed_tests_max_attempts: settings.ci.test_management_attempt_to_fix_retries_count,
            dynamic_atr_enabled: settings.ci.dynamic_atr_enabled,
            dynamic_atr_buckets: settings.ci.dynamic_atr_buckets
          )

          @test_management = TestManagement::Component.build(
            enabled: settings.ci.test_management_enabled,
            api: test_visibility_api,
            git_commit_head_sha: settings.ci.git_commit_head_sha
          )

          # @type ivar @test_impact_analysis: Datadog::CI::TestImpactAnalysis::Component
          @test_impact_analysis = build_test_impact_analysis(settings, test_visibility_api)
          @test_tracing = TestTracing::Component.build(
            tracer: @tracer,
            api: test_visibility_api,
            dd_env: settings.env,
            config_tags: custom_configuration(settings),
            logical_test_session_name: settings.ci.test_session_name,
            runtime_tags_overrides: Utils::RuntimeTagsOverrides.parse(settings.ci.runtime_tags_overrides),
            context_service_uri: settings.ci.test_visibility_drb_server_uri,
            trace_setup_teardown_enabled: settings.ci.trace_setup_teardown_enabled
          )

          @agentless_logs_submission = build_agentless_logs_component(settings, test_visibility_api)

          @impacted_tests_detection = ImpactedTestsDetection::Component.new(
            enabled: settings.ci.impacted_tests_detection_enabled,
            base_branch: settings.ci.git_pull_request_base_branch,
            base_commit_sha: settings.ci.git_pull_request_base_branch_sha,
            target_commit_sha: settings.ci.git_commit_head_sha
          )

          @code_coverage = build_code_coverage(settings, test_visibility_api)
        end

        def build_test_impact_analysis(settings, test_visibility_api)
          if settings.ci.itr_code_coverage_use_single_threaded_mode &&
              settings.ci.itr_test_impact_analysis_use_allocation_tracing
            Datadog::CI.logger.warn(
              "Test Impact Analysis: Single threaded coverage mode is incompatible with allocation tracing. " \
              "Allocation tracing will be disabled. It means that test impact analysis will not be able to detect " \
              "instantiations of objects in your code, which is important for ActiveRecord models. " \
              "Please add your app/model folder to the list of tracked files or disable single threaded coverage mode."
            )

            settings.ci.itr_test_impact_analysis_use_allocation_tracing = false
          end

          if RUBY_VERSION.start_with?("3.2.") &&
              Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2.3") &&
              settings.ci.itr_test_impact_analysis_use_allocation_tracing
            Datadog::CI.logger.warn(
              "Test Impact Analysis: Allocation tracing is not supported in Ruby versions 3.2.0, 3.2.1 and 3.2.2 and will be forcibly " \
              "disabled. This is due to a VM bug that can lead to crashes (https://bugs.ruby-lang.org/issues/19482). " \
              "Please update your Ruby version or add your app/model folder to the list of tracked files." \
              "Set env variable DD_CIVISIBILITY_ITR_TEST_IMPACT_ANALYSIS_USE_ALLOCATION_TRACING to 0 to disable this warning."
            )
            settings.ci.itr_test_impact_analysis_use_allocation_tracing = false
          end

          TestImpactAnalysis::Component.build(
            api: test_visibility_api,
            discard_traces: settings.ci.discard_traces,
            dd_env: settings.env,
            config_tags: custom_configuration(settings),
            test_skipping_mode: settings.ci.tia_test_skipping_mode,
            enabled: settings.ci.enabled && settings.ci.itr_enabled,
            bundle_location: settings.ci.itr_code_coverage_excluded_bundle_path,
            use_single_threaded_coverage: settings.ci.itr_code_coverage_use_single_threaded_mode,
            use_allocation_tracing: settings.ci.itr_test_impact_analysis_use_allocation_tracing,
            static_dependencies_tracking_enabled: settings.ci.tia_static_dependencies_tracking_enabled,
            opened_files_coverage_enabled: settings.ci.tia_opened_files_coverage_enabled
          )
        end

        def build_test_visibility_api(settings)
          if settings.ci.agentless_mode_enabled
            check_dd_site(settings)

            Datadog::CI.logger.debug("Test Optimization configured to use agentless transport")

            api = Transport::Api::Builder.build_agentless_api(settings)
            if api.nil?
              Datadog::CI.logger.error do
                "DATADOG CONFIGURATION - TEST OPTIMIZATION - ATTENTION - " \
                "Agentless mode was enabled but DD_API_KEY is not set: Test Optimization is disabled. " \
                "Please make sure to set valid api key in DD_API_KEY environment variable"
              end

              # Tests are running without Test Optimization enabled
              settings.ci.enabled = false
            end
          else
            Datadog::CI.logger.debug("Test Optimization configured to use agent transport via EVP proxy")

            api, agent_available = Transport::Api::Builder.build_evp_proxy_api(settings)
            if api.nil?
              if agent_available
                Datadog::CI.logger.error(
                  "Test Optimization cannot use the configured Datadog Agent because it does not support EVP proxy. " \
                  "Disabling Test Optimization. Please upgrade the Datadog Agent."
                )
              else
                Datadog::CI.logger.error(
                  "Test Optimization cannot connect to the Datadog Agent. " \
                  "Disabling Test Optimization. Please ensure the Agent is running and configured to accept traces."
                )
              end

              settings.ci.enabled = false
            end
          end

          api
        end

        def build_git_upload_worker(settings, api)
          if settings.ci.git_metadata_upload_enabled
            git_tree_uploader = Git::TreeUploader.new(api: api, force_unshallow: settings.ci.impacted_tests_detection_enabled)
            Worker.new do |repository_url, commit_sha|
              git_tree_uploader.call(repository_url, commit_sha: commit_sha)
            end
          else
            DummyWorker.new
          end
        end

        def build_code_coverage(settings, api)
          CodeCoverage::Component.build(
            enabled: settings.ci.code_coverage_report_upload_enabled,
            api: api,
            discard_traces: settings.ci.discard_traces,
            flags: settings.ci.code_coverage_flags
          )
        end

        def build_agentless_logs_component(settings, api)
          if settings.ci.agentless_logs_submission_enabled && !settings.ci.agentless_mode_enabled
            Datadog::CI.logger.warn(
              "Agentless logs submission is enabled but agentless mode is not enabled. " \
              "Logs will not be submitted. " \
              "Please make sure to set DD_CIVISIBILITY_AGENTLESS_ENABLED to true if you want to submit logs in agentless mode. " \
              "Otherwise, set DD_AGENTLESS_LOG_SUBMISSION_ENABLED to 0 and use Datadog Agent to submit logs."
            )
            settings.ci.agentless_logs_submission_enabled = false
          end

          Logs::Component.build(
            enabled: settings.ci.agentless_logs_submission_enabled,
            api: api,
            discard_traces: settings.ci.discard_traces
          )
        end

        # fetch custom tags provided by the user in DD_TAGS env var
        # with prefix test.configuration.
        def custom_configuration(settings)
          @custom_configuration ||= Utils::TestRun.custom_configuration(settings.tags)
        end

        def check_dd_site(settings)
          return if settings.site.nil?
          return if Ext::Settings::DD_SITE_ALLOWLIST.include?(settings.site)

          Datadog::CI.logger.warn do
            "TEST OPTIMIZATION CONFIGURATION " \
            "Agentless mode was enabled but DD_SITE is not set to one of the following: #{Ext::Settings::DD_SITE_ALLOWLIST.join(", ")}. " \
            "Please make sure to set valid site in DD_SITE environment variable"
          end
        end

        def configure_telemetry(settings)
          return unless settings.telemetry.enabled

          agentless = settings.ci.agentless_mode_enabled || settings.telemetry.agentless_enabled
          if agentless
            url = URI.parse(settings.telemetry.agentless_url_override ||
              "https://instrumentation-telemetry-intake.#{settings.site || Ext::Transport::DEFAULT_DD_SITE}")
            client = Transport::Adapters::Net.new(
              hostname: url.host, port: url.port, ssl: url.scheme == "https", timeout_seconds: 5.0
            )
          else
            agent = Transport::Api::Builder.resolve_agent_settings(settings)
            client = Transport::Adapters::Net.new(
              hostname: agent.hostname, port: agent.port, ssl: agent.ssl,
              timeout_seconds: agent.timeout_seconds, uds_path: agent.uds_path
            )
          end
          @telemetry = Telemetry::Component.new(
            client: client,
            logger: CI.logger,
            application: {
              "service_name" => settings.service || "ruby",
              "env" => settings.env,
              "service_version" => settings.version,
              "language_name" => "ruby",
              "language_version" => RUBY_VERSION,
              "runtime_name" => RUBY_ENGINE,
              "runtime_version" => RUBY_ENGINE_VERSION,
              "tracer_version" => CI::VERSION::STRING
            },
            host: {"hostname" => Utils::Platform.hostname, "os" => RbConfig::CONFIG["host_os"], "architecture" => RbConfig::CONFIG["host_cpu"]},
            runtime_id_provider: -> { Utils::Identity.id },
            agentless: agentless,
            api_key: settings.api_key,
            aggregation_interval: settings.telemetry.aggregation_interval,
            buffer_size: settings.telemetry.buffer_size,
            shutdown_timeout: settings.telemetry.shutdown_timeout_seconds,
            debug: settings.diagnostics.debug
          )
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

        private

        def event_tags(tags, env, version)
          tags.dup.tap do |result|
            result["env"] = env unless env.nil?
            result["version"] = version unless version.nil?
          end
        end

        def shutdown_component(name)
          yield
        rescue => error
          CI.logger.warn("Failed to shut down Test Optimization #{name}: #{error.class}: #{error.message}")
        end
      end
    end
  end
end
