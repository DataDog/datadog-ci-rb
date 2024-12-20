RSpec.describe Datadog::CI::Contrib::Cucumber::Integration do
  extend GemsHelpers

  let(:integration) { described_class.new }

  describe ".version" do
    subject(:version) { integration.version }

    context 'when the "cucumber" gem is loaded' do
      include_context "loaded gems", "cucumber" => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "cucumber" gem is not loaded' do
      include_context "loaded gems", "cucumber" => nil
      it { is_expected.to be nil }
    end
  end

  describe ".loaded?" do
    subject(:loaded?) { integration.loaded? }

    context "when Cucumber::Runtime is defined" do
      before { stub_const("Cucumber::Runtime", Class.new) }

      it { is_expected.to be true }
    end

    context "when Cucumber::Runtime is not defined" do
      before { hide_const("Cucumber::Runtime") }

      it { is_expected.to be false }
    end
  end

  describe ".compatible?" do
    subject(:compatible?) { integration.compatible? }

    context 'when "cucumber" gem is loaded with a version' do
      context "that is less than the minimum" do
        include_context "loaded gems", "cucumber" => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context "that meets the minimum version" do
        include_context "loaded gems", "cucumber" => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context "when gem is not loaded" do
      include_context "loaded gems", "cucumber" => nil
      it { is_expected.to be false }
    end
  end

  describe "#late_instrument?" do
    subject(:late_instrument?) { integration.late_instrument? }

    it { is_expected.to be(false) }
  end

  describe "#configuration" do
    subject(:configuration) { integration.configuration }

    it { is_expected.to be_a_kind_of(Datadog::CI::Contrib::Cucumber::Configuration::Settings) }
  end

  describe "#patcher" do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::CI::Contrib::Cucumber::Patcher }
  end
end
