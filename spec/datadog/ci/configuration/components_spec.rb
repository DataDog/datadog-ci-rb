# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/configuration/components"

RSpec.describe Datadog::CI::Configuration::Components do
  context "when used to extend Datadog::Core::Configuration::Components" do
    subject(:components) do
      # When 'datadog/ci' is required, it automatically extends Components.
      components = if described_class >= Datadog::Core::Configuration::Components
        Datadog::Core::Configuration::Components.new(settings)
      else
        components_class = Datadog::Core::Configuration::Components.dup
        components_class.prepend(described_class)
        components_class.new(settings)
      end

      components
    end

    let(:settings) do
      # When 'datadog/ci' is required, it automatically extends Settings.
      if Datadog::Core::Configuration::Settings <= Datadog::CI::Configuration::Settings
        Datadog::Core::Configuration::Settings.new
      else
        Datadog::Core::Configuration::Settings.new.tap do |settings|
          settings.extend(Datadog::CI::Configuration::Settings)
        end
      end
    end

    after do
      components.shutdown!
    end

    describe "::new" do
      context "when #ci" do
        before do
          # Configure CI mode
          settings.tracing.enabled = tracing_enabled
          settings.ci.enabled = enabled
          settings.ci.agentless_mode_enabled = agentless_enabled
          settings.ci.agentless_logs_submission_enabled = agentless_logs_submission_enabled

          settings.ci.force_test_level_visibility = force_test_level_visibility
          settings.ci.agentless_url = agentless_url
          settings.ci.itr_enabled = itr_enabled
          settings.ci.itr_code_coverage_use_single_threaded_mode = itr_code_coverage_use_single_threaded_mode
          settings.ci.itr_test_impact_analysis_use_allocation_tracing = itr_test_impact_analysis_use_allocation_tracing
          settings.ci.discard_traces = discard_traces
          settings.site = dd_site
          settings.api_key = api_key

          negotiation = double(:negotiation)

          telemetry_double = instance_double(
            Datadog::Core::Telemetry::Component,
            emit_closing!: nil,
            stop!: nil
          )
          allow(Datadog::Core::Telemetry::Component).to receive(:build).and_return(telemetry_double)

          allow(Datadog::Core::Remote::Negotiation)
            .to receive(:new)
            .and_return(negotiation)

          allow(negotiation)
            .to receive(:endpoint?).with("/evp_proxy/v4/")
            .and_return(evp_proxy_v4_supported)

          allow(negotiation)
            .to receive(:endpoint?).with("/evp_proxy/v2/")
            .and_return(evp_proxy_v2_supported)

          # Spy on test mode behavior
          allow(settings.tracing.test_mode)
            .to receive(:enabled=).and_call_original

          allow(settings.tracing.test_mode)
            .to receive(:trace_flush=).and_call_original

          allow(settings.tracing.test_mode)
            .to receive(:writer_options=).and_call_original

          allow(settings.tracing.test_mode)
            .to receive(:async=).and_call_original

          allow(settings.telemetry).to receive(:enabled=).and_call_original
          allow(settings.telemetry).to receive(:agentless_enabled=).and_call_original

          allow(Datadog::CI::Ext::Environment)
            .to receive(:tags).and_return({})

          logger = spy(:logger)
          allow(Datadog).to receive(:logger).and_return(logger)

          allow(Datadog.logger)
            .to receive(:debug)

          allow(Datadog.logger)
            .to receive(:warn)

          allow(Datadog.logger)
            .to receive(:error)

          components

          allow(Datadog).to receive(:components).and_return(components)
        end

        let(:api_key) { nil }
        let(:agentless_url) { nil }
        let(:dd_site) { nil }
        let(:agentless_enabled) { false }
        let(:agentless_logs_submission_enabled) { false }
        let(:force_test_level_visibility) { false }
        let(:evp_proxy_v2_supported) { false }
        let(:evp_proxy_v4_supported) { false }
        let(:itr_enabled) { false }
        let(:tracing_enabled) { true }
        let(:itr_code_coverage_use_single_threaded_mode) { false }
        let(:itr_test_impact_analysis_use_allocation_tracing) { true }
        let(:discard_traces) { false }

        context "is enabled" do
          let(:enabled) { true }

          context "when tracing is disabled" do
            let(:tracing_enabled) { false }

            it "logs an error message and disables Test Optimization" do
              expect(Datadog.logger).to have_received(:error)

              expect(settings.ci.enabled).to eq(false)
            end
          end

          context "when #force_test_level_visibility" do
            let(:evp_proxy_v2_supported) { true }

            context "is false" do
              it "creates test visibility component with test_suite_level_visibility_enabled=true" do
                expect(components.test_visibility).to be_kind_of(Datadog::CI::TestVisibility::Component)
                expect(components.test_visibility.test_suite_level_visibility_enabled).to eq(true)
              end
            end

            context "is true" do
              let(:force_test_level_visibility) { true }

              it "creates test visibility component with test_suite_level_visibility_enabled=false" do
                expect(components.test_visibility).to be_kind_of(Datadog::CI::TestVisibility::Component)
                expect(components.test_visibility.test_suite_level_visibility_enabled).to eq(false)
              end
            end
          end

          context "and when #agentless_mode" do
            context "is disabled" do
              let(:agentless_enabled) { false }

              context "when environment value for telemetry is not present" do
                it "enables telemetry" do
                  expect(settings.telemetry).to have_received(:enabled=).with(true)
                end

                it "patches Datadog::Core::Telemetry::Http::Adapters::Net" do
                  expect(Datadog::Core::Telemetry::Http::Adapters::Net).to be < Datadog::CI::Transport::Adapters::TelemetryWebmockSafeAdapter
                end
              end

              context "when environment value for telemetry is present" do
                around do |example|
                  ClimateControl.modify(Datadog::Core::Telemetry::Ext::ENV_ENABLED => telemetry_enabled) do
                    example.run
                  end
                end

                context "when telemetry is explicitly disabled" do
                  let(:telemetry_enabled) { "false" }

                  it "disables telemetry" do
                    expect(settings.telemetry).to have_received(:enabled=).with(false)
                  end
                end

                context "when telemetry is explicitly enabled" do
                  let(:telemetry_enabled) { "true" }

                  it "enables telemetry" do
                    expect(settings.telemetry).to have_received(:enabled=).with(true)
                  end
                end
              end

              context "and when agent supports EVP proxy v2" do
                let(:evp_proxy_v2_supported) { true }

                it "sets async for test mode and constructs transport with EVP proxy API" do
                  expect(settings.tracing.test_mode)
                    .to have_received(:async=)
                    .with(true)

                  expect(settings.tracing.test_mode).to have_received(:writer_options=) do |options|
                    expect(options[:transport]).to be_kind_of(Datadog::CI::TestVisibility::Transport)
                    expect(options[:transport].api).to be_kind_of(Datadog::CI::Transport::Api::EvpProxy)
                    expect(options[:shutdown_timeout]).to eq(60)
                  end
                end
              end

              context "and when agent supports EVP proxy v4" do
                let(:evp_proxy_v4_supported) { true }

                it "sets async for test mode and constructs transport with EVP proxy API" do
                  expect(settings.tracing.test_mode)
                    .to have_received(:async=)
                    .with(true)

                  expect(settings.tracing.test_mode).to have_received(:writer_options=) do |options|
                    expect(options[:transport]).to be_kind_of(Datadog::CI::TestVisibility::Transport)
                    expect(options[:transport].api).to be_kind_of(Datadog::CI::Transport::Api::EvpProxy)
                    expect(options[:shutdown_timeout]).to eq(60)
                  end
                end
              end

              context "and when agent does not support EVP proxy" do
                let(:itr_enabled) { true }

                it "falls back to default transport and disables test suite level visibility and ITR" do
                  expect(settings.tracing.test_mode)
                    .to have_received(:enabled=)
                    .with(true)

                  expect(settings.tracing.test_mode)
                    .to have_received(:trace_flush=)
                    .with(settings.ci.trace_flush || kind_of(Datadog::CI::TestVisibility::Flush::Partial))

                  expect(settings.ci.force_test_level_visibility).to eq(true)
                  expect(settings.ci.itr_enabled).to eq(false)

                  expect(settings.tracing.test_mode).to have_received(:writer_options=) do |options|
                    expect(options[:transport]).to be_nil
                  end

                  expect(components.test_visibility.itr_enabled?).to eq(false)
                end
              end

              context "and when discard_traces setting is enabled" do
                let(:discard_traces) { true }

                it "sets tracing transport to TestVisibility::NullTransport" do
                  expect(settings.tracing.test_mode).to have_received(:writer_options=) do |options|
                    expect(options[:transport]).to be_kind_of(Datadog::CI::TestVisibility::NullTransport)
                  end
                end
              end
            end

            context "is enabled" do
              let(:agentless_enabled) { true }

              context "when api key is set" do
                let(:api_key) { "api_key" }

                it "enables telemetry by default" do
                  expect(settings.telemetry).to have_received(:enabled=).with(true)
                  expect(settings.telemetry).to have_received(:agentless_enabled=).with(true)
                end

                it "sets async for test mode and constructs transport with CI intake API" do
                  expect(Datadog.logger).not_to have_received(:warn)
                  expect(Datadog.logger).not_to have_received(:error)

                  expect(settings.tracing.test_mode)
                    .to have_received(:async=)
                    .with(true)

                  expect(settings.tracing.test_mode).to have_received(:writer_options=) do |options|
                    expect(options[:transport]).to be_kind_of(Datadog::CI::TestVisibility::Transport)
                    expect(options[:transport].api).to be_kind_of(Datadog::CI::Transport::Api::Agentless)
                    expect(options[:shutdown_timeout]).to eq(60)
                  end
                end

                context "when DD_SITE is set to a wrong value" do
                  let(:dd_site) { "wrong" }

                  it "logs a warning" do
                    expect(Datadog.logger).to have_received(:warn) do |*_args, &block|
                      expect(block.call).to match(
                        /TEST OPTIMIZATION CONFIGURATION Agentless mode was enabled but DD_SITE is not set to one of the following/
                      )
                    end
                  end
                end

                context "when DD_SITE is set to a correct value" do
                  let(:dd_site) { "datadoghq.eu" }

                  it "does not log a warning" do
                    expect(Datadog.logger).not_to have_received(:warn)
                  end
                end

                context "when ITR is disabled" do
                  let(:itr_enabled) { false }

                  it "creates test visibility component with ITR disabled" do
                    expect(components.test_visibility.itr_enabled?).to eq(false)
                  end
                end

                context "when ITR is enabled" do
                  let(:itr_enabled) { true }

                  it "creates test visibility component with ITR enabled" do
                    expect(components.test_visibility.itr_enabled?).to eq(true)
                    expect(settings.ci.itr_test_impact_analysis_use_allocation_tracing).to eq(true)
                  end

                  context "when single threaded mode for line coverage is enabled" do
                    let(:itr_code_coverage_use_single_threaded_mode) { true }

                    it "logs a warning and disables allocation tracing for ITR" do
                      expect(Datadog.logger).to have_received(:warn)

                      expect(settings.ci.itr_test_impact_analysis_use_allocation_tracing).to eq(false)
                    end
                  end
                end
              end

              context "when api key is not set" do
                let(:api_key) { nil }
                let(:itr_enabled) { true }

                it "logs an error message and disables Test Optimization" do
                  expect(Datadog.logger).to have_received(:error)

                  expect(settings.ci.enabled).to eq(false)
                  expect(components.test_visibility.itr_enabled?).to eq(false)
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
                  expect(Datadog.logger).to have_received(:error).with(
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

          it do
            expect(settings.tracing.test_mode)
              .to_not have_received(:enabled=)
          end

          it do
            expect(settings.tracing.test_mode)
              .to_not have_received(:trace_flush=)
          end

          it do
            expect(settings.tracing.test_mode)
              .to_not have_received(:writer_options=)
          end
        end
      end
    end
  end
end
