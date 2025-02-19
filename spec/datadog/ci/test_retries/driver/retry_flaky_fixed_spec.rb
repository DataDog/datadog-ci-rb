require_relative "../../../../../lib/datadog/ci/test_retries/driver/retry_flaky_fixed"

RSpec.describe Datadog::CI::TestRetries::Driver::RetryFlakyFixed do
  let(:max_attempts) { 10 }
  let(:test_span) { double(:test_span, set_tag: true) }

  subject(:driver) { described_class.new(max_attempts: max_attempts) }

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
end
