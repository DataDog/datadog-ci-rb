RSpec.describe ::Datadog::CI::Utils::Configuration do
  describe ".fetch_service_name" do
    subject { described_class.fetch_service_name(default) }

    let(:default) { "default" }

    before do
      allow(::Datadog.configuration).to receive(:service_without_fallback).and_return(service)
    end

    context "when service is set in Datadog config" do
      let(:service) { "service_without_fallback" }

      it { is_expected.to eq(service) }
    end

    context "when service is not set" do
      let(:service) { nil }

      before do
        expect(::Datadog::CI::Utils::Git).to receive(:repository_name).and_return(repository_name)
      end

      context "when repository_name can be fetched" do
        let(:repository_name) { "repository_name" }

        it { is_expected.to eq(repository_name) }
      end

      context "when repository_name can not be fetched" do
        let(:repository_name) { nil }

        it { is_expected.to eq(default) }
      end
    end
  end
end
