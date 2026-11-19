# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/configuration/components"

RSpec.describe Datadog::CI::Configuration::Components do
  context "with an independent CI runtime" do
    subject(:components) { described_class.new(settings) }

    let(:settings) { Datadog::CI::Configuration::RuntimeSettings.new }

    after do
      components.shutdown!
    end

    describe "::new" do
      context "when #ci" do
        before do
          # Configure CI mode
          Datadog.configuration.tracing.enabled = tracing_enabled
          settings.ci.enabled = enabled
          settings.ci.agentless_mode_enabled = agentless_enabled
          settings.ci.agentless_logs_submission_enabled = agentless_logs_submission_enabled
          settings.ci.trace_setup_teardown_enabled = trace_setup_teardown_enabled

          settings.ci.agentless_url = agentless_url
          settings.ci.itr_enabled = itr_enabled
          settings.ci.tia_test_skipping_mode = tia_test_skipping_mode
          unless tia_static_dependencies_tracking_enabled.nil?
            settings.ci.tia_static_dependencies_tracking_enabled = tia_static_dependencies_tracking_enabled
          end
          unless tia_opened_files_coverage_enabled.nil?
            settings.ci.tia_opened_files_coverage_enabled = tia_opened_files_coverage_enabled
          end
          settings.ci.itr_code_coverage_use_single_threaded_mode = itr_code_coverage_use_single_threaded_mode
          settings.ci.itr_test_impact_analysis_use_allocation_tracing = itr_test_impact_analysis_use_allocation_tracing
          settings.ci.discard_traces = discard_traces
          settings.ci.test_discovery_enabled = test_discovery_enabled
          settings.ci.minitest_no_plugins = minitest_no_plugins
          settings.ci.code_coverage_flags = code_coverage_flags
          settings.ci.writer_options = writer_options
          settings.site = dd_site
          settings.api_key = api_key

          endpoints = [
            ("/evp_proxy/v4/" if evp_proxy_v4_supported),
            ("/evp_proxy/v2/" if evp_proxy_v2_supported)
          ].compact
          agent_info_response = instance_double(
            Datadog::CI::Transport::Adapters::Net::Response,
            error: (IOError.new("agent unavailable") unless agent_available),
            ok?: agent_available,
            payload: JSON.generate("endpoints" => endpoints)
          )
          allow(Datadog::CI::Transport::HTTP).to receive(:new).and_wrap_original do |constructor, **options|
            constructor.call(**options).tap do |transport|
              allow(transport).to receive(:request).and_call_original
              allow(transport).to receive(:request)
                .with(path: "/info", payload: anything, headers: {}, verb: "get")
                .and_return(agent_info_response)
            end
          end
          allow(Datadog::CI::Telemetry::Component).to receive(:new).and_call_original

          allow(Datadog::CI::Ext::Environment)
            .to receive(:tags).and_return({})

          allow(Datadog::CI::TestImpactAnalysis::Component).to receive(:new).and_call_original
          allow(Datadog::CI::Remote::LibrarySettingsClient).to receive(:new).and_call_original
          allow(Datadog::CI::CodeCoverage::Component).to receive(:new).and_call_original

          logger = spy(:logger)
          allow(Datadog::CI).to receive(:logger).and_return(logger)

          allow(Datadog::CI.logger)
            .to receive(:debug)

          allow(Datadog::CI.logger)
            .to receive(:warn)

          allow(Datadog::CI.logger)
            .to receive(:error)

          stub_const("RUBY_VERSION", ruby_version)

          components

          allow(Datadog::CI).to receive(:components).and_return(components)
        end

        let(:api_key) { nil }
        let(:agentless_url) { nil }
        let(:dd_site) { nil }
        let(:agentless_enabled) { false }
        let(:agentless_logs_submission_enabled) { false }
        let(:trace_setup_teardown_enabled) { false }
        let(:evp_proxy_v2_supported) { true }
        let(:evp_proxy_v4_supported) { false }
        let(:agent_available) { true }
        let(:itr_enabled) { false }
        let(:tia_test_skipping_mode) { "test" }
        let(:tia_static_dependencies_tracking_enabled) { nil }
        let(:tia_opened_files_coverage_enabled) { nil }
        let(:tracing_enabled) { true }
        let(:ruby_version) { RUBY_VERSION }
        let(:itr_code_coverage_use_single_threaded_mode) { false }
        let(:itr_test_impact_analysis_use_allocation_tracing) { true }
        let(:discard_traces) { false }
        let(:test_discovery_enabled) { false }
        let(:minitest_no_plugins) { nil }
        let(:code_coverage_flags) { nil }
        let(:writer_options) { {} }

        context "is enabled" do
          let(:enabled) { true }

          context "when setup and teardown tracing is enabled" do
            let(:trace_setup_teardown_enabled) { true }

            it "passes the setting to test tracing" do
              expect(components.test_tracing.trace_setup_teardown_enabled).to be(true)
            end
          end

          it "owns the event tracer and writer independently of application test mode" do
            expect(components.tracer).to be_a(Datadog::CI::EventTracer)
            expect(components.tracer.writer).to be_a(Datadog::CI::EventWriter)
            expect(Datadog::CI::EventWriter).to have_received(:new).with(
              hash_including(transport: components.tracer.writer.transport, shutdown_timeout: 60)
            )
            expect(Datadog.configuration.tracing.test_mode.enabled).to be(false)
          end

          context "when DD_SYMBOL_DATABASE_UPLOAD_ENABLED is true" do
            around do |example|
              ClimateControl.modify("DD_SYMBOL_DATABASE_UPLOAD_ENABLED" => "true") { example.run }
            end

            it "leaves application Symbol Database configuration unchanged" do
              expect(Datadog.configuration.symbol_database.enabled).to be(true)
            end
          end

          it "shuts down Test Optimization components before telemetry" do
            shutdown_order = []
            allow(components.test_impact_analysis).to receive(:shutdown!) { shutdown_order << :test_impact_analysis }
            allow(components.telemetry).to receive(:shutdown!) { shutdown_order << :telemetry }

            components.shutdown!

            expect(shutdown_order).to eq([:test_impact_analysis, :telemetry])
          end

          it "attempts each shutdown once and attempts telemetry last when all components fail" do
            targets = [
              [components.test_optimization_cache, :shutdown!],
              [components.test_tracing, :shutdown!],
              [components.test_impact_analysis, :shutdown!],
              [components.agentless_logs_submission, :shutdown!],
              [components.test_discovery, :shutdown!],
              [components.code_coverage, :shutdown!],
              [components.git_tree_upload_worker, :stop],
              [components.tracer_bridge, :shutdown!],
              [components.tracer, :shutdown!],
              [components.telemetry, :shutdown!]
            ]
            shutdown_order = []
            targets.each_with_index do |(component, method), index|
              allow(component).to receive(method) do
                shutdown_order << index
                raise "shutdown failed"
              end
            end

            expect { 2.times { components.shutdown! } }.not_to raise_error
            expect(shutdown_order).to eq((0...targets.length).to_a)
            expect(Datadog::CI.logger).to have_received(:warn).with(/Failed to shut down Test Optimization/).exactly(targets.length).times
          end

          context "when writer options are configured" do
            let(:writer_options) { {buffer_size: 100, interval: 0.2, shutdown_timeout: 3} }

            it "passes the legacy interval and limits to the event writer" do
              expect(Datadog::CI::EventWriter).to have_received(:new).with(
                hash_including(buffer_size: 100, flush_interval: 0.2, shutdown_timeout: 3)
              )
            end
          end

          context "when application tracing is disabled" do
            let(:tracing_enabled) { false }

            it "keeps Test Optimization enabled" do
              expect(settings.ci.enabled).to be(true)
              expect(components.test_tracing).to be_a(Datadog::CI::TestTracing::Component)
              expect(Datadog.configuration.tracing.enabled).to be(false)
            end
          end

          context "when static dependencies tracking is enabled by default" do
            let(:agentless_enabled) { true }
            let(:api_key) { "api_key" }

            it "passes the default value to test impact analysis" do
              expect(Datadog::CI::TestImpactAnalysis::Component).to have_received(:new).with(
                hash_including(static_dependencies_tracking_enabled: true)
              )
            end

            context "when the setting is explicitly disabled" do
              let(:tia_static_dependencies_tracking_enabled) { false }

              it "passes the configured value to test impact analysis" do
                expect(Datadog::CI::TestImpactAnalysis::Component).to have_received(:new).with(
                  hash_including(static_dependencies_tracking_enabled: false)
                )
              end
            end
          end

          context "when opened files coverage is enabled by default" do
            let(:agentless_enabled) { true }
            let(:api_key) { "api_key" }

            it "passes the default value to test impact analysis" do
              expect(Datadog::CI::TestImpactAnalysis::Component).to have_received(:new).with(
                hash_including(opened_files_coverage_enabled: true)
              )
            end

            context "when the setting is explicitly disabled" do
              let(:tia_opened_files_coverage_enabled) { false }

              it "passes the configured value to test impact analysis" do
                expect(Datadog::CI::TestImpactAnalysis::Component).to have_received(:new).with(
                  hash_including(opened_files_coverage_enabled: false)
                )
              end
            end
          end

          context "when code coverage flags are configured" do
            let(:agentless_enabled) { true }
            let(:api_key) { "api_key" }
            let(:code_coverage_flags) { "type:unit-tests,jvm-21" }

            it "passes them to the code coverage component" do
              expect(Datadog::CI::CodeCoverage::Component).to have_received(:new).with(
                hash_including(flags: code_coverage_flags)
              )
            end
          end

          context "when test suite skipping mode is configured" do
            let(:agentless_enabled) { true }
            let(:api_key) { "api_key" }
            let(:tia_test_skipping_mode) { "suite" }

            it "passes the configured mode to Test Impact Analysis and remote settings" do
              expect(Datadog::CI::TestImpactAnalysis::Component).to have_received(:new).with(
                hash_including(test_skipping_mode: "suite")
              )
              expect(Datadog::CI::Remote::LibrarySettingsClient).to have_received(:new).with(
                hash_including(test_skipping_mode: "suite")
              )
            end
          end

          context "and when #agentless_mode" do
            context "is disabled" do
              let(:agentless_enabled) { false }

              context "when environment value for telemetry is not present" do
                it "enables telemetry" do
                  expect(components.telemetry.enabled?).to be(true)
                end

                it "uses an independent HTTP adapter for telemetry" do
                  expect(Datadog::CI::Telemetry::Component).to have_received(:new).with(
                    hash_including(client: a_kind_of(Datadog::CI::Transport::Adapters::Net), agentless: false)
                  )
                end
              end

              context "when environment value for telemetry is present" do
                around do |example|
                  ClimateControl.modify("DD_INSTRUMENTATION_TELEMETRY_ENABLED" => telemetry_enabled) do
                    example.run
                  end
                end

                context "when telemetry is explicitly disabled" do
                  let(:telemetry_enabled) { "false" }

                  it "disables telemetry" do
                    expect(components.telemetry.enabled?).to be(false)
                  end
                end

                context "when telemetry is explicitly enabled" do
                  let(:telemetry_enabled) { "true" }

                  it "enables telemetry" do
                    expect(components.telemetry.enabled?).to be(true)
                  end
                end
              end

              context "and when agent supports EVP proxy v2" do
                let(:evp_proxy_v2_supported) { true }

                it "constructs the event writer with EVP proxy transport" do
                  transport = components.tracer.writer.transport
                  expect(transport).to be_a(Datadog::CI::TestTracing::Transport)
                  expect(transport.api).to be_a(Datadog::CI::Transport::Api::EvpProxy)
                end
              end

              context "and when agent supports EVP proxy v4" do
                let(:evp_proxy_v4_supported) { true }

                it "constructs the event writer with EVP proxy transport" do
                  transport = components.tracer.writer.transport
                  expect(transport).to be_a(Datadog::CI::TestTracing::Transport)
                  expect(transport.api).to be_a(Datadog::CI::Transport::Api::EvpProxy)
                end
              end

              context "and when agent does not support EVP proxy" do
                let(:evp_proxy_v2_supported) { false }

                it "logs an unsupported Agent error and disables Test Optimization" do
                  expect(Datadog::CI.logger).to have_received(:error).with(
                    "Test Optimization cannot use the configured Datadog Agent because it does not support EVP proxy. " \
                    "Disabling Test Optimization. Please upgrade the Datadog Agent."
                  )
                  expect(settings.ci.enabled).to eq(false)
                  expect(components.test_tracing).to be_kind_of(Datadog::CI::TestTracing::NullComponent)
                  expect(components.ci_remote).to be_kind_of(Datadog::CI::Remote::NullComponent)
                  expect(components.test_retries).to be_kind_of(Datadog::CI::TestRetries::NullComponent)
                end
              end

              context "and when the agent is unavailable" do
                let(:evp_proxy_v2_supported) { false }
                let(:agent_available) { false }

                it "logs an unavailable Agent error and disables Test Optimization" do
                  expect(Datadog::CI.logger).to have_received(:error).with(
                    "Test Optimization cannot connect to the Datadog Agent. " \
                    "Disabling Test Optimization. Please ensure the Agent is running and configured to accept traces."
                  )
                  expect(settings.ci.enabled).to eq(false)
                  expect(components.test_tracing).to be_kind_of(Datadog::CI::TestTracing::NullComponent)
                  expect(components.ci_remote).to be_kind_of(Datadog::CI::Remote::NullComponent)
                  expect(components.test_retries).to be_kind_of(Datadog::CI::TestRetries::NullComponent)
                end
              end

              context "and when discard_traces setting is enabled" do
                let(:discard_traces) { true }

                it "sets tracing transport to TestTracing::NullTransport" do
                  expect(components.tracer.writer.transport).to be_a(Datadog::CI::TestTracing::NullTransport)
                end
              end
            end

            context "is enabled" do
              let(:agentless_enabled) { true }

              context "when api key is set" do
                let(:api_key) { "api_key" }

                it "enables telemetry by default" do
                  expect(components.telemetry.enabled?).to be(true)
                  expect(Datadog::CI::Telemetry::Component).to have_received(:new).with(
                    hash_including(agentless: true, api_key: "api_key")
                  )
                end

                it "constructs the event writer with CI intake transport" do
                  expect(Datadog::CI.logger).not_to have_received(:warn)
                  expect(Datadog::CI.logger).not_to have_received(:error)
                  transport = components.tracer.writer.transport
                  expect(transport).to be_a(Datadog::CI::TestTracing::Transport)
                  expect(transport.api).to be_a(Datadog::CI::Transport::Api::Agentless)
                end

                context "when DD_SITE is set to a wrong value" do
                  let(:dd_site) { "wrong" }

                  it "logs a warning" do
                    expect(Datadog::CI.logger).to have_received(:warn) do |*_args, &block|
                      expect(block.call).to match(
                        /TEST OPTIMIZATION CONFIGURATION Agentless mode was enabled but DD_SITE is not set to one of the following/
                      )
                    end
                  end
                end

                context "when DD_SITE is set to a correct value" do
                  let(:dd_site) { "datadoghq.eu" }

                  it "does not log a warning" do
                    expect(Datadog::CI.logger).not_to have_received(:warn)
                  end
                end

                context "when ITR is disabled" do
                  let(:itr_enabled) { false }

                  it "creates test visibility component with ITR disabled" do
                    expect(components.test_tracing.itr_enabled?).to eq(false)
                  end
                end

                context "when ITR is enabled" do
                  let(:itr_enabled) { true }

                  it "creates test visibility component with ITR enabled" do
                    expect(components.test_tracing.itr_enabled?).to eq(true)
                    expect(settings.ci.itr_test_impact_analysis_use_allocation_tracing).to eq(true)
                  end

                  context "when single threaded mode for line coverage is enabled" do
                    let(:itr_code_coverage_use_single_threaded_mode) { true }

                    it "logs a warning and disables allocation tracing for ITR" do
                      expect(Datadog::CI.logger).to have_received(:warn)

                      expect(settings.ci.itr_test_impact_analysis_use_allocation_tracing).to eq(false)
                    end
                  end

                  context "when running on a Ruby version affected by the allocation tracing VM bug" do
                    let(:ruby_version) { "3.2.2" }

                    it "logs a warning and disables allocation tracing for ITR" do
                      expect(Datadog::CI.logger).to have_received(:warn).with(/Allocation tracing is not supported/)

                      expect(settings.ci.itr_test_impact_analysis_use_allocation_tracing).to eq(false)
                    end
                  end

                  context "when running on a Ruby 3.2 patch version that is not affected by the VM bug" do
                    # Regression test: a previous lexicographic compare
                    # (`RUBY_VERSION < "3.2.3"`) incorrectly fired here because
                    # "3.2.11" < "3.2.3" is true as a string compare.
                    let(:ruby_version) { "3.2.11" }

                    it "does not log a warning and leaves allocation tracing enabled" do
                      expect(Datadog::CI.logger).not_to have_received(:warn).with(/Allocation tracing is not supported/)

                      expect(settings.ci.itr_test_impact_analysis_use_allocation_tracing).to eq(true)
                    end
                  end
                end

                context "when test discovery is enabled with other features" do
                  let(:test_discovery_enabled) { true }
                  let(:itr_enabled) { true }
                  let(:agentless_logs_submission_enabled) { true }

                  it "disables other features" do
                    expect(settings.ci.test_discovery_enabled).to eq(true)
                    expect(settings.ci.discard_traces).to eq(true)
                    expect(settings.ci.itr_enabled).to eq(false)
                    expect(settings.ci.agentless_logs_submission_enabled).to eq(false)
                  end

                  it "enables Minitest plugin auto-loading by default" do
                    expect(components.test_discovery.minitest_plugin_autoload_enabled?).to be(true)
                  end

                  context "when Minitest plugin auto-loading is disabled" do
                    let(:minitest_no_plugins) { "0" }

                    it "passes the opt-out to discovery" do
                      expect(components.test_discovery.minitest_plugin_autoload_enabled?).to be(false)
                    end
                  end
                end
              end

              context "when api key is not set" do
                let(:api_key) { nil }
                let(:itr_enabled) { true }

                it "logs an error message and disables Test Optimization" do
                  expect(Datadog::CI.logger).to have_received(:error)

                  expect(settings.ci.enabled).to eq(false)
                  expect(components.test_tracing.itr_enabled?).to eq(false)
                end
              end
            end
          end

          context "and when agentless_logs_submission" do
            context "is enabled" do
              let(:agentless_logs_submission_enabled) { true }

              context "when agentless mode is enabled" do
                let(:agentless_enabled) { true }
                let(:api_key) { "api_key" }

                it "creates logs component with enabled=true" do
                  expect(components.agentless_logs_submission).to be_kind_of(Datadog::CI::Logs::Component)
                  expect(components.agentless_logs_submission.enabled).to eq(true)
                end
              end

              context "when agentless mode is disabled" do
                let(:agentless_enabled) { false }

                it "logs an error and disables agentless logs submission" do
                  expect(Datadog::CI.logger).to have_received(:warn).with(
                    /Agentless logs submission is enabled but agentless mode is not enabled./
                  )

                  expect(settings.ci.agentless_logs_submission_enabled).to eq(false)
                  expect(components.agentless_logs_submission).to be_kind_of(Datadog::CI::Logs::Component)
                  expect(components.agentless_logs_submission.enabled).to eq(false)
                end
              end
            end

            context "is disabled" do
              let(:agentless_logs_submission_enabled) { false }

              it "creates logs component with enabled=false" do
                expect(components.agentless_logs_submission).to be_kind_of(Datadog::CI::Logs::Component)
                expect(components.agentless_logs_submission.enabled).to eq(false)
              end
            end
          end
        end

        context "is disabled" do
          let(:enabled) { false }
          let(:agentless_enabled) { false }

          context "when DD_SYMBOL_DATABASE_UPLOAD_ENABLED is true" do
            around do |example|
              ClimateControl.modify("DD_SYMBOL_DATABASE_UPLOAD_ENABLED" => "true") { example.run }
            end

            it "leaves Symbol Database upload enabled" do
              expect(Datadog.configuration.symbol_database.enabled).to be(true)
            end
          end

          it "uses inactive components and discards events" do
            expect(components.test_tracing).to be_a(Datadog::CI::TestTracing::NullComponent)
            expect(components.tracer_bridge).to be_a(Datadog::CI::TracerBridge::NullComponent)
            expect(components.telemetry.enabled?).to be(false)
            expect(components.tracer.writer.transport).to be_a(Datadog::CI::TestTracing::NullTransport)
            expect(Datadog.configuration.tracing.test_mode.enabled).to be(false)
          end
        end
      end
    end
  end
end
