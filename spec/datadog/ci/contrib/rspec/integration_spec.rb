RSpec.describe Datadog::CI::Contrib::RSpec::Integration do
  extend GemsHelpers

  let(:integration) { described_class.new }

  describe ".version" do
    subject(:version) { integration.version }

    context 'when the "rspec-core" gem is loaded' do
      include_context "loaded gems", "rspec-core" => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "rspec-core" gem is not loaded' do
      include_context "loaded gems", "rspec-core" => nil
      it { is_expected.to be nil }
    end
  end

  describe ".loaded?" do
    subject(:loaded?) { integration.loaded? }

    context "when RSpec is defined" do
      it { is_expected.to be true }
    end
  end

  describe ".compatible?" do
    subject(:compatible?) { integration.compatible? }

    context 'when "rspec-core" gem is loaded with a version' do
      context "that is less than the minimum" do
        include_context "loaded gems", "rspec-core" => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context "that meets the minimum version" do
        include_context "loaded gems", "rspec-core" => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context "when gem is not loaded" do
      include_context "loaded gems", "rspec-core" => nil
      it { is_expected.to be false }
    end
  end

  describe "#late_instrument?" do
    subject(:late_instrument?) { integration.late_instrument? }

    it { is_expected.to be(false) }
  end

  describe "#configuration" do
    subject(:configuration) { integration.configuration }

    it { is_expected.to be_a_kind_of(Datadog::CI::Contrib::RSpec::Configuration::Settings) }
  end

  describe "#patcher" do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::CI::Contrib::RSpec::Patcher }
  end

  describe "#new_configuration" do
    subject(:new_configuration) { integration.new_configuration }

    context "when test discovery component is enabled" do
      before do
        allow(integration).to receive(:test_discovery_component).and_return(
          double("test_discovery_component", enabled?: true)
        )
      end

      it "creates settings with dry_run_enabled set to true" do
        expect(new_configuration.dry_run_enabled).to be true
      end
    end

    context "when test discovery component is disabled" do
      before do
        allow(integration).to receive(:test_discovery_component).and_return(
          double("test_discovery_component", enabled?: false)
        )
      end

      it "creates settings with dry_run_enabled set to false" do
        expect(new_configuration.dry_run_enabled).to be false
      end
    end
  end
end
