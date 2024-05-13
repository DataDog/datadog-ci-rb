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

          settings.ci.force_test_level_visibility = force_test_level_visibility
          settings.ci.agentless_url = agentless_url
          settings.ci.itr_enabled = itr_enabled
          settings.site = dd_site
          settings.api_key = api_key

          negotiation = double(:negotiation)

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

          allow(Datadog.logger)
            .to receive(:debug)

          allow(Datadog.logger)
            .to receive(:warn)

          allow(Datadog.logger)
            .to receive(:error)

          allow(Datadog::CI::Ext::Environment)
            .to receive(:tags).and_return({})

          components
        end

        let(:api_key) { nil }
        let(:agentless_url) { nil }
        let(:dd_site) { nil }
        let(:agentless_enabled) { false }
        let(:force_test_level_visibility) { false }
        let(:evp_proxy_v2_supported) { false }
        let(:evp_proxy_v4_supported) { false }
        let(:itr_enabled) { false }
        let(:tracing_enabled) { true }

        context "is enabled" do
          let(:enabled) { true }

          it "collects environment tags" do
            expect(Datadog::CI::Ext::Environment).to have_received(:tags).with(ENV)
          end

          context "when tracing is disabled" do
            let(:tracing_enabled) { false }

            it "logs an error message and disables CI visibility" do
              expect(Datadog.logger).to have_received(:error)

              expect(settings.ci.enabled).to eq(false)
            end
          end

          context "when #force_test_level_visibility" do
            let(:evp_proxy_v2_supported) { true }

            context "is false" do
              it "creates a CI recorder with test_suite_level_visibility_enabled=true" do
                expect(components.ci_recorder).to be_kind_of(Datadog::CI::TestVisibility::Recorder)
                expect(components.ci_recorder.test_suite_level_visibility_enabled).to eq(true)
              end
            end

            context "is true" do
              let(:force_test_level_visibility) { true }

              it "creates a CI recorder with test_suite_level_visibility_enabled=false" do
                expect(components.ci_recorder).to be_kind_of(Datadog::CI::TestVisibility::Recorder)
                expect(components.ci_recorder.test_suite_level_visibility_enabled).to eq(false)
              end
            end
          end

          context "and when #agentless_mode" do
            context "is disabled" do
              let(:agentless_enabled) { false }

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

                  expect(components.ci_recorder.itr_enabled?).to eq(false)
                end
              end
            end

            context "is enabled" do
              let(:agentless_enabled) { true }

              context "when api key is set" do
                let(:api_key) { "api_key" }

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
                        /CI VISIBILITY CONFIGURATION Agentless mode was enabled but DD_SITE is not set to one of the following/
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

                  it "creates a CI recorder with ITR disabled" do
                    expect(components.ci_recorder.itr_enabled?).to eq(false)
                  end
                end

                context "when ITR is enabled" do
                  let(:itr_enabled) { true }

                  it "creates a CI recorder with ITR enabled" do
                    expect(components.ci_recorder.itr_enabled?).to eq(true)
                  end
                end
              end

              context "when api key is not set" do
                let(:api_key) { nil }
                let(:itr_enabled) { true }

                it "logs an error message and disables CI visibility" do
                  expect(Datadog.logger).to have_received(:error)

                  expect(settings.ci.enabled).to eq(false)
                  expect(components.ci_recorder.itr_enabled?).to eq(false)
                end
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

          it "does not collect tags" do
            expect(Datadog::CI::Ext::Environment).not_to have_received(:tags)
          end
        end
      end
    end
  end
end
