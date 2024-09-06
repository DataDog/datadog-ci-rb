require_relative "../../../../../lib/datadog/ci/test_retries/strategy/retry_new"

RSpec.describe Datadog::CI::TestRetries::Strategy::RetryNew do
  let(:max_attempts) { 10 }
  let(:duration_thresholds) {
    Datadog::CI::Remote::SlowTestRetries.new({
      "5s" => 10,
      "10s" => 5,
      "30s" => 3,
      "10m" => 2
    })
  }
  subject(:strategy) { described_class.new(duration_thresholds: duration_thresholds) }

  describe "#should_retry?" do
    subject { strategy.should_retry? }
    let(:test_span) { double(:test_span, set_tag: true) }

    context "when max attempts haven't been reached yet" do
      it { is_expected.to be true }
    end

    context "when the max attempts have been reached" do
      before { max_attempts.times { strategy.record_retry(test_span) } }

      it { is_expected.to be false }
    end
  end

  describe "#record_duration" do
    subject { strategy.record_duration(duration) }

    let(:duration) { 5 }

    it "updates the max attempts based on the duration" do
      expect { subject }.to change { strategy.instance_variable_get(:@max_attempts) }.from(10).to(5)
    end
  end
end