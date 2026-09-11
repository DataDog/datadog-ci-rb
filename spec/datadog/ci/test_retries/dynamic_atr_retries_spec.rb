# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_retries/dynamic_atr_retries"
require_relative "../../../../lib/datadog/ci/remote/slow_test_retries"

RSpec.describe Datadog::CI::TestRetries::DynamicATRRetries do
  describe ".enabled?" do
    subject { described_class.enabled? }

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_ENABLED is unset" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_ENABLED" => nil) { example.run } }

      it { is_expected.to be false }
    end

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_ENABLED is false" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_ENABLED" => "false") { example.run } }

      it { is_expected.to be false }
    end

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_ENABLED is true" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_ENABLED" => "true") { example.run } }

      it { is_expected.to be true }
    end

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_ENABLED is 1" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_ENABLED" => "1") { example.run } }

      it { is_expected.to be true }
    end
  end

  describe ".buckets" do
    subject { described_class.buckets }

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS is unset" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS" => nil) { example.run } }

      it { is_expected.to be_nil }
    end

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS is empty" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS" => "") { example.run } }

      it { is_expected.to be_nil }
    end

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS has valid five integers" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS" => "10,4,1,1,1") { example.run } }

      it { is_expected.to eq([10, 4, 1, 1, 1]) }
    end

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS has wrong count" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS" => "10,4,1") { example.run } }

      it { is_expected.to be_nil }
    end

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS has a value < 1" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS" => "10,4,0,1,1") { example.run } }

      it { is_expected.to be_nil }
    end

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS has a value > 20" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS" => "21,4,1,1,1") { example.run } }

      it { is_expected.to be_nil }
    end

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS has non-integers" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS" => "invalid") { example.run } }

      it { is_expected.to be_nil }
    end

    context "when DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS has mixed non-integers" do
      around { |example| ClimateControl.modify("DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS" => "not,enough,values") { example.run } }

      it { is_expected.to be_nil }
    end
  end
end
