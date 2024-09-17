require_relative "../../../../../lib/datadog/ci/test_retries/driver/retry_failed"

RSpec.describe Datadog::CI::TestRetries::Driver::RetryFailed do
  let(:max_attempts) { 3 }
  subject(:driver) { described_class.new(max_attempts: max_attempts) }

  describe "#should_retry?" do
    subject { driver.should_retry? }

    context "when the test has not passed yet" do
      let(:test_span) { double(:test_span, set_tag: true, passed?: false) }

      it { is_expected.to be true }

      context "when the max attempts have been reached" do
        before { max_attempts.times { driver.record_retry(test_span) } }

        it { is_expected.to be false }
      end
    end

    context "when the test has passed" do
      let(:test_span) { double(:test_span, set_tag: true, passed?: true) }

      before { driver.record_retry(test_span) }

      it { is_expected.to be false }
    end
  end
end
