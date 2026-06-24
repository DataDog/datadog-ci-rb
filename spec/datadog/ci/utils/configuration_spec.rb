# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/utils/configuration"

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
        expect(::Datadog::CI::Git::LocalRepository).to receive(:repository_name).and_return(repository_name)
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

  describe ".service_name_provided_by_user?" do
    subject { described_class.service_name_provided_by_user? }

    before do
      allow(::Datadog.configuration).to receive(:service_without_fallback).and_return(service)
    end

    context "when service is set in Datadog config" do
      let(:service) { "service_without_fallback" }

      it { is_expected.to be true }
    end

    context "when service is not set" do
      let(:service) { nil }

      it { is_expected.to be false }
    end
  end

  describe ".normalize_tia_test_skipping_mode" do
    subject(:normalize_tia_test_skipping_mode) { described_class.normalize_tia_test_skipping_mode(mode) }

    context "when mode is test" do
      let(:mode) { Datadog::CI::Ext::Test::TIATestSkippingMode::TEST }

      it { is_expected.to eq("test") }
    end

    context "when mode is suite" do
      let(:mode) { Datadog::CI::Ext::Test::TIATestSkippingMode::SUITE }

      it { is_expected.to eq("suite") }
    end

    context "when mode is invalid" do
      let(:mode) { "invalid" }

      it "logs a warning and returns test mode" do
        expect(Datadog.logger).to receive(:warn).with(/Invalid Test Impact Analysis skipping mode/)

        expect(normalize_tia_test_skipping_mode).to eq("test")
      end
    end
  end
end
