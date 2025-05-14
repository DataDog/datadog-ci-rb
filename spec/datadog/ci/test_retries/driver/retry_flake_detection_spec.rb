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
  let(:test_span) { double(:test_span, set_tag: true) }

  subject(:driver) { described_class.new(test_span, max_attempts_thresholds: max_attempts_thresholds) }

  describe "#should_retry?" do
    subject { driver.should_retry? }

    context "when max attempts haven't been reached yet" do
      it { is_expected.to be true }
    end

    context "when the max attempts have been reached" do
      before { max_attempts.times { driver.record_retry(test_span) } }

      it { is_expected.to be false }
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
