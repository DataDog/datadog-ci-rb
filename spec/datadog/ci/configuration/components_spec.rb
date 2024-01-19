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
      components.telemetry.worker.stop(true)
      components.telemetry.worker.join
      components.shutdown!
    end

    describe "::new" do
      context "when #ci" do
        before do
          # Stub CI mode behavior
          allow(settings.ci)
            .to receive(:enabled)
            .and_return(enabled)

          allow(settings.ci)
            .to receive(:agentless_mode_enabled)
            .and_return(agentless_enabled)

          allow(settings.ci)
            .to receive(:use_test_level_visibility)
            .and_return(use_test_level_visibility)

          allow(settings.ci)
            .to receive(:agentless_url)
            .and_return(agentless_url)

          allow(settings)
            .to receive(:site)
            .and_return(dd_site)

          allow(settings)
            .to receive(:api_key)
            .and_return(api_key)

          negotiation = double(:negotiation)

          allow(Datadog::Core::Remote::Negotiation)
            .to receive(:new)
            .and_return(negotiation)

          allow(negotiation)
            .to receive(:endpoint?).with("/evp_proxy/v2/")
            .and_return(evp_proxy_supported)

          # Spy on test mode behavior
          allow(settings.tracing.test_mode)
            .to receive(:enabled=)

          allow(settings.tracing.test_mode)
            .to receive(:trace_flush=)

          allow(settings.tracing.test_mode)
            .to receive(:writer_options=)

          allow(settings.tracing.test_mode)
            .to receive(:async=)

          allow(settings.ci)
            .to receive(:enabled=)

          allow(settings.ci)
            .to receive(:use_test_level_visibility=)

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
        let(:use_test_level_visibility) { false }
        let(:evp_proxy_supported) { false }

        context "is enabled" do
          let(:enabled) { true }

          it "collects environment tags" do
            expect(Datadog::CI::Ext::Environment).to have_received(:tags).with(ENV)
          end

          context "when #use_test_level_visibility" do
            context "is false" do
              it "creates a CI recorder with test_suite_level_visibility_enabled=true" do
                expect(components.ci_recorder).to be_kind_of(Datadog::CI::TestVisibility::Recorder)
                expect(components.ci_recorder.test_suite_level_visibility_enabled).to eq(true)
              end
            end

            context "is true" do
              let(:use_test_level_visibility) { true }

              it "creates a CI recorder with test_suite_level_visibility_enabled=false" do
                expect(components.ci_recorder).to be_kind_of(Datadog::CI::TestVisibility::Recorder)
                expect(components.ci_recorder.test_suite_level_visibility_enabled).to eq(false)
              end
            end
          end

          context "and when #agentless_mode" do
            context "is disabled" do
              let(:agentless_enabled) { false }

              context "and when agent supports EVP proxy" do
                let(:evp_proxy_supported) { true }

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
                let(:evp_proxy_supported) { false }

                it "falls back to default transport and disables test suite level visibility" do
                  expect(settings.tracing.test_mode)
                    .to have_received(:enabled=)
                    .with(true)

                  expect(settings.tracing.test_mode)
                    .to have_received(:trace_flush=)
                    .with(settings.ci.trace_flush || kind_of(Datadog::CI::TestVisibility::Flush::Partial))

                  expect(settings.ci)
                    .to have_received(:use_test_level_visibility=)
                    .with(true)

                  expect(settings.tracing.test_mode).to have_received(:writer_options=) do |options|
                    expect(options[:transport]).to be_nil
                  end
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
                    expect(options[:transport].api).to be_kind_of(Datadog::CI::Transport::Api::CiTestCycle)
                    expect(options[:shutdown_timeout]).to eq(60)
                  end
                end
              end

              context "when DD_SITE is set to a wrong value" do
                let(:dd_site) { "wrong" }

                it "logs a warning" do
                  expect(Datadog.logger).to have_received(:warn).with(
                    /CI VISIBILITY CONFIGURATION Agentless mode was enabled but DD_SITE is not set to one of the following/
                  )
                end
              end

              context "when DD_SITE is set to a correct value" do
                let(:dd_site) { "datadoghq.eu" }

                it "logs a warning" do
                  expect(Datadog.logger).not_to have_received(:warn)
                end
              end

              context "when api key is not set" do
                let(:api_key) { nil }

                it "logs an error message and disables CI visibility" do
                  expect(Datadog.logger).to have_received(:error)
                  expect(settings.ci).to have_received(:enabled=).with(false)
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
