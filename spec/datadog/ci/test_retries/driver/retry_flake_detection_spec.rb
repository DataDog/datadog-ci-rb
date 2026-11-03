require_relative "../../../../../lib/datadog/ci/test_retries/driver/retry_flake_detection"

RSpec.describe Datadog::CI::TestRetries::Driver::RetryFlakeDetection do
  let(:max_attempts) { 9 }
  let(:max_attempts_thresholds) {
    Datadog::CI::Remote::SlowTestRetries.new({
      "5s" => 10,
      "10s" => 5,
      "30s" => 3,
      "10m" => 2
    })
  }
  let(:first_test_passed) { true }
  let(:first_test_failed) { false }
  let(:test_span) { double(:test_span, set_internal_tag: true, passed?: first_test_passed, failed?: first_test_failed) }

  subject(:driver) { described_class.new(test_span, max_attempts_thresholds: max_attempts_thresholds) }

  before { driver.record_duration(1.0) }

  describe "#should_retry?" do
    subject { driver.should_retry? }

    context "when the first test passed" do
      let(:first_test_passed) { true }
      let(:first_test_failed) { false }

      it { is_expected.to be true }

      context "when the max attempts have been reached" do
        before { max_attempts.times { driver.record_retry(test_span) } }

        it { is_expected.to be false }
      end

      context "when a retry fails (flakiness detected)" do
        let(:failed_span) { double(:test_span, set_internal_tag: true, passed?: false, failed?: true) }

        before { driver.record_retry(failed_span) }

        it { is_expected.to be false }
      end
    end

    context "when the first test failed" do
      let(:first_test_passed) { false }
      let(:first_test_failed) { true }

      it { is_expected.to be true }

      context "when a retry passes (flakiness detected)" do
        let(:passed_span) { double(:test_span, set_internal_tag: true, passed?: true, failed?: false) }

        before { driver.record_retry(passed_span) }

        it { is_expected.to be false }
      end

      context "when retries keep failing" do
        let(:failed_span) { double(:test_span, set_internal_tag: true, passed?: false, failed?: true) }

        before { 3.times { driver.record_retry(failed_span) } }

        it { is_expected.to be true }
      end
    end

    context "when all retries pass without any failure" do
      let(:first_test_passed) { true }
      let(:first_test_failed) { false }
      let(:passed_span) { double(:test_span, set_internal_tag: true, passed?: true, failed?: false) }

      before { 5.times { driver.record_retry(passed_span) } }

      it { is_expected.to be true }
    end
  end

  describe "duration classification" do
    it "uses the original duration for all executions" do
      driver.record_duration(600.0)
      8.times { driver.record_retry(test_span) }
      expect(driver.should_retry?).to be true
      driver.record_retry(test_span)
      expect(driver.should_retry?).to be false
    end

    [0, 1, 2, 3].each do |executions|
      context "with #{executions} total executions configured" do
        let(:max_attempts_thresholds) { Datadog::CI::Remote::SlowTestRetries.new("5s" => executions) }

        it "counts the original execution in the budget" do
          [executions - 1, 0].max.times do
            expect(driver.should_retry?).to be true
            driver.record_retry(test_span)
          end
          expect(driver.should_retry?).to be false
        end
      end
    end
  end
end
