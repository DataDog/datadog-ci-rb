require_relative "../../../../../lib/datadog/ci/test_retries/driver/retry_flaky_fixed"

RSpec.describe Datadog::CI::TestRetries::Driver::RetryFlakyFixed do
  let(:max_attempts) { 10 }
  let(:passing_span) { double(:test_span, set_tag: true, failed?: false) }
  let(:failing_span) { double(:test_span, set_tag: true, failed?: true) }

  subject(:driver) { described_class.new(first_test_span, max_attempts: max_attempts) }

  describe "#should_retry?" do
    subject { driver.should_retry? }

    context "when the first test passed" do
      let(:first_test_span) { passing_span }

      it { is_expected.to be true }

      context "when the max attempts have been reached" do
        before { max_attempts.times { driver.record_retry(passing_span) } }

        it { is_expected.to be false }
      end

      context "when a retry fails" do
        before { driver.record_retry(failing_span) }

        it { is_expected.to be false }
      end

      context "when retries keep passing" do
        before { 5.times { driver.record_retry(passing_span) } }

        it { is_expected.to be true }
      end
    end

    context "when the first test failed" do
      let(:first_test_span) { failing_span }

      it { is_expected.to be false }
    end
  end
end
