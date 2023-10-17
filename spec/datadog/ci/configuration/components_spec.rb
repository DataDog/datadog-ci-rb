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
            .to receive(:agentless_url)
            .and_return(agentless_url)

          allow(settings)
            .to receive(:site)
            .and_return(dd_site)

          allow(settings)
            .to receive(:api_key)
            .and_return(api_key)

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

          allow(Datadog.logger)
            .to receive(:error)

          components
        end

        let(:api_key) { nil }
        let(:agentless_url) { nil }
        let(:dd_site) { nil }

        context "is enabled" do
          let(:enabled) { true }

          context "and when #agentless_mode" do
            context "is disabled" do
              let(:agentless_enabled) { false }

              it do
                expect(settings.tracing.test_mode)
                  .to have_received(:enabled=)
                  .with(true)
              end

              it do
                expect(settings.tracing.test_mode)
                  .to have_received(:trace_flush=)
                  .with(settings.ci.trace_flush || kind_of(Datadog::CI::TestVisibility::Flush::Finished))
              end

              it do
                expect(settings.tracing.test_mode)
                  .to have_received(:writer_options=)
                  .with(settings.ci.writer_options)
              end
            end

            context "is enabled" do
              let(:agentless_enabled) { true }

              context "when api key is set" do
                let(:api_key) { "api_key" }

                it "sets async for test mode and provides transport and shutdown timeout to the writer" do
                  expect(settings.tracing.test_mode)
                    .to have_received(:async=)
                    .with(true)

                  expect(settings.tracing.test_mode).to have_received(:writer_options=) do |options|
                    expect(options[:transport]).to be_kind_of(Datadog::CI::TestVisibility::Transport)
                    expect(options[:shutdown_timeout]).to eq(60)
                  end
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
        end
      end
    end
  end
end
