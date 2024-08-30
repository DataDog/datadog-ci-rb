# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/remote/slow_test_retries"

RSpec.describe Datadog::CI::Remote::SlowTestRetries do
  let(:payload) do
    {
      "5m" => 2,
      "5s" => 10,
      "30s" => 3,
      "10s" => 5,
      "ffdsfdsfds" => nil,
      "10m" => nil,
      "10h" => 12
    }
  end

  subject(:slow_test_retries) { described_class.new(payload) }

  describe "#initialize" do
    subject { slow_test_retries.entries }

    it do
      is_expected.to eq([
        described_class::Entry.new(5.0, 10),
        described_class::Entry.new(10.0, 5),
        described_class::Entry.new(30.0, 3),
        described_class::Entry.new(300.0, 2),
        described_class::Entry.new(600.0, 0)
      ])
    end
  end

  describe "#max_attempts_for_duration" do
    subject { slow_test_retries.max_attempts_for_duration(duration) }

    context "when the duration is less than 5 seconds" do
      let(:duration) { 4.9 }

      it { is_expected.to eq(10) }
    end

    context "when the duration is less than 10 seconds" do
      let(:duration) { 9.9 }

      it { is_expected.to eq(5) }
    end

    context "when the duration is less than 30 seconds" do
      let(:duration) { 29.9 }

      it { is_expected.to eq(3) }
    end

    context "when the duration is less than 5 minutes" do
      let(:duration) { 299.9 }

      it { is_expected.to eq(2) }
    end

    context "when the duration is less than 10 minutes" do
      let(:duration) { 599.9 }

      it { is_expected.to eq(0) }
    end

    context "when the duration is more than 10 minutes" do
      let(:duration) { 600.1 }

      it { is_expected.to eq(1) }
    end
  end
end
