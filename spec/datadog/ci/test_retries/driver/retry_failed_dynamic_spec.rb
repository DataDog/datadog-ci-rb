# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/test_retries/driver/retry_failed_dynamic"
require_relative "../../../../../lib/datadog/ci/remote/slow_test_retries"

RSpec.describe Datadog::CI::TestRetries::Driver::RetryFailedDynamic do
  let(:slow_test_retries) do
    Datadog::CI::Remote::SlowTestRetries.new({
      "5s" => 10,
      "10s" => 2,
      "30s" => 3,
      "5m" => 4
    })
  end

  let(:test_span) { double(:test_span, set_tag: true, passed?: false, failed?: true) }

  subject(:driver) { described_class.new(slow_test_retries, retries_buckets: retries_buckets) }

  describe "#should_retry? with EFD buckets (no custom buckets)" do
    let(:retries_buckets) { nil }

    context "when duration is in 5s bucket" do
      before { driver.record_duration(1.0) }

      it "retries up to the 5s budget (10)" do
        10.times { driver.record_retry(test_span) }
        expect(driver.should_retry?).to be false
      end
    end

    context "when duration is in 10s bucket" do
      before { driver.record_duration(6.0) }

      it "retries up to the 10s budget (2)" do
        2.times { driver.record_retry(test_span) }
        expect(driver.should_retry?).to be false
      end
    end

    context "when duration is in 30s bucket" do
      before { driver.record_duration(31.0) }

      it "retries up to the 5m budget (4)" do
        4.times { driver.record_retry(test_span) }
        expect(driver.should_retry?).to be false
      end
    end

    context "when duration is > 5 minutes" do
      before { driver.record_duration(301.0) }

      it "still retries at least once (max(1, 0))" do
        expect(driver.should_retry?).to be true
        driver.record_retry(test_span)
        expect(driver.should_retry?).to be false
      end
    end
  end

  describe "#should_retry? with custom buckets" do
    let(:retries_buckets) { [4, 1, 1, 1, 1] }

    context "when duration is in 5s bucket" do
      before { driver.record_duration(1.0) }

      it "retries up to the custom 5s budget (4)" do
        4.times { driver.record_retry(test_span) }
        expect(driver.should_retry?).to be false
      end
    end

    context "when duration is in 10s bucket" do
      before { driver.record_duration(6.0) }

      it "retries up to the custom 10s budget (1)" do
        driver.record_retry(test_span)
        expect(driver.should_retry?).to be false
      end
    end
  end

  describe "#should_retry? when test passes" do
    let(:retries_buckets) { [5, 1, 1, 1, 1] }
    let(:passing_span) { double(:test_span, set_tag: true, passed?: true, failed?: false) }

    before { driver.record_duration(1.0) }

    it "stops retrying after a pass" do
      expect(driver.should_retry?).to be true
      driver.record_retry(passing_span)
      expect(driver.should_retry?).to be false
    end
  end

  describe "#record_duration caching" do
    let(:retries_buckets) { nil }

    it "classifies once and ignores subsequent record_duration calls" do
      driver.record_duration(1.0)  # 5s bucket -> 10 retries
      expect(driver.max_attempts).to eq(10)

      driver.record_duration(301.0)  # >5m bucket would be 0, but should be ignored
      expect(driver.max_attempts).to eq(10)
    end
  end

  describe "#should_retry? ignoring flat retry count" do
    let(:retries_buckets) { [3, 1, 1, 1, 1] }

    it "uses the dynamic budget regardless of DD_CIVISIBILITY_FLAKY_RETRY_COUNT" do
      # The flat limit env var is irrelevant to the dynamic driver
      driver.record_duration(1.0)
      expect(driver.max_attempts).to eq(3)

      3.times { driver.record_retry(test_span) }
      expect(driver.should_retry?).to be false
    end
  end

  describe "#retry_reason" do
    let(:retries_buckets) { nil }

    subject { driver.retry_reason }

    it { is_expected.to eq(Datadog::CI::Ext::Test::RetryReason::RETRY_FAILED) }
  end
end
