# Dummy Integration
class FakeIntegration
  module Patcher
    module_function

    def patched?
      @patched
    end

    def patch
      @patched = true
    end

    def reset
      @patched = nil
    end
  end

  def self.loaded?
    true
  end

  def self.compatible?
    true
  end

  def self.auto_instrument?
    false
  end

  def patcher
    Patcher
  end
end

RSpec.describe Datadog::CI::Configuration::Settings do
  context "when used to extend Datadog::Core::Configuration::Settings" do
    subject(:settings) do
      # When 'datadog/ci' is required, it automatically extends Settings.
      if described_class >= Datadog::Core::Configuration::Settings
        Datadog::Core::Configuration::Settings.new
      else
        Datadog::Core::Configuration::Settings.new.tap do |settings|
          settings.extend(described_class)
        end
      end
    end

    describe "#ci" do
      describe "#enabled" do
        subject(:enabled) { settings.ci.enabled }

        it { is_expected.to be false }

        context "when #{Datadog::CI::Ext::Settings::ENV_MODE_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::CI::Ext::Settings::ENV_MODE_ENABLED => enable) do
              example.run
            end
          end

          context "is not defined" do
            let(:enable) { nil }

            it { is_expected.to be false }
          end

          context "is set to true" do
            let(:enable) { "true" }

            it { is_expected.to be true }
          end

          context "is set to false" do
            let(:enable) { "false" }

            it { is_expected.to be false }
          end
        end
      end

      describe "#enabled=" do
        it "updates the #enabled setting" do
          expect { settings.ci.enabled = true }
            .to change { settings.ci.enabled }
            .from(false)
            .to(true)
        end
      end

      describe "#instrument" do
        let(:registry) { {} }
        let(:integration_name) { :fake }

        subject(:instrument) { settings.ci.instrument(integration_name) }

        before do
          registry[integration_name] = instance_double(
            Datadog::CI::Contrib::Integration::RegisteredIntegration,
            klass: FakeIntegration
          )

          allow(Datadog::CI::Contrib::Integration).to receive(:registry).and_return(registry)
          settings.ci.enabled = ci_enabled
        end

        after do
          FakeIntegration::Patcher.reset
        end

        context "ci enabled" do
          let(:ci_enabled) { true }

          context "when integration exists" do
            context "when loaded and compatible" do
              it "patches the integration" do
                expect(FakeIntegration::Patcher).to receive(:patch)

                instrument
              end
            end

            context "when called multiple times" do
              it "does not patch the integration multiple times" do
                expect(FakeIntegration::Patcher).to receive(:patch).and_call_original.once

                instrument
                instrument
              end
            end

            context "when not loaded" do
              before { expect(FakeIntegration).to receive(:loaded?).and_return(false) }

              it "does not patch the integration" do
                expect(FakeIntegration::Patcher).to_not receive(:patch)

                instrument
              end
            end

            context "when loaded and not compatible" do
              before { expect(FakeIntegration).to receive(:compatible?).and_return(false) }

              it "does not patch the integration" do
                expect(FakeIntegration::Patcher).to_not receive(:patch)

                instrument
              end
            end

            context "when integration does not exist" do
              let(:integration_name) { :not_exiting }

              it "does not patch the integration" do
                expect { instrument }.to_not raise_error
              end
            end
          end

          context "ci is not enabled" do
            let(:ci_enabled) { false }

            it "does not patch the integration" do
              expect(FakeIntegration::Patcher).to_not receive(:patch)
              instrument
            end
          end
        end
      end

      describe "#trace_flush" do
        subject(:trace_flush) { settings.ci.trace_flush }

        context "default" do
          it { is_expected.to be nil }
        end
      end

      describe "#trace_flush=" do
        let(:trace_flush) { instance_double(Datadog::Tracing::Flush::Finished) }

        it "updates the #trace_flush setting" do
          expect { settings.ci.trace_flush = trace_flush }
            .to change { settings.ci.trace_flush }
            .from(nil)
            .to(trace_flush)
        end
      end

      describe "#writer_options" do
        subject(:writer_options) { settings.ci.writer_options }

        it { is_expected.to eq({}) }

        context "when modified" do
          it "does not modify the default by reference" do
            settings.ci.writer_options[:foo] = :bar
            expect(settings.ci.writer_options).to_not be_empty
            expect(settings.ci.options[:writer_options].default_value).to be_empty
          end
        end
      end

      describe "#writer_options=" do
        let(:options) { {priority_sampling: true} }

        it "updates the #writer_options setting" do
          expect { settings.ci.writer_options = options }
            .to change { settings.ci.writer_options }
            .from({})
            .to(options)
        end
      end
    end
  end
end
