require_relative "../../../../../lib/datadog/ci/test_retries/driver/retry_flake_detection"

RSpec.describe Datadog::CI::TestRetries::Driver::RetryFlakeDetection do
  let(:max_attempts) { 10 }
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
  let(:test_span) { double(:test_span, set_tag: true, passed?: first_test_passed, failed?: first_test_failed) }

  subject(:driver) { described_class.new(test_span, max_attempts_thresholds: max_attempts_thresholds) }

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
        let(:failed_span) { double(:test_span, set_tag: true, passed?: false, failed?: true) }

        before { driver.record_retry(failed_span) }

        it { is_expected.to be false }
      end
    end

    context "when the first test failed" do
      let(:first_test_passed) { false }
      let(:first_test_failed) { true }

      it { is_expected.to be true }

      context "when a retry passes (flakiness detected)" do
        let(:passed_span) { double(:test_span, set_tag: true, passed?: true, failed?: false) }

        before { driver.record_retry(passed_span) }

        it { is_expected.to be false }
      end

      context "when retries keep failing" do
        let(:failed_span) { double(:test_span, set_tag: true, passed?: false, failed?: true) }

        before { 3.times { driver.record_retry(failed_span) } }

        it { is_expected.to be true }
      end
    end

    context "when all retries pass without any failure" do
      let(:first_test_passed) { true }
      let(:first_test_failed) { false }
      let(:passed_span) { double(:test_span, set_tag: true, passed?: true, failed?: false) }

      before { 5.times { driver.record_retry(passed_span) } }

      it { is_expected.to be true }
    end
  end

  describe "#record_duration" do
    subject { driver.record_duration(duration) }

    let(:duration) { 5 }

    it "updates the max attempts based on the duration" do
      expect { subject }.to change { driver.instance_variable_get(:@max_attempts) }.from(10).to(5)
    end
  end
end
