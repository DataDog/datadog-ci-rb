require_relative "../../../../lib/datadog/ci/test_retries/component"

RSpec.describe Datadog::CI::TestRetries::Component do
  let(:library_settings) { instance_double(Datadog::CI::Remote::LibrarySettings) }
  let(:retry_failed_tests_max_attempts) { 1 }
  let(:retry_failed_tests_total_limit) { 12 }

  subject(:component) do
    described_class.new(
      retry_failed_tests_max_attempts: retry_failed_tests_max_attempts,
      retry_failed_tests_total_limit: retry_failed_tests_total_limit
    )
  end

  describe "#configure" do
    subject { component.configure(library_settings) }

    context "when flaky test retries are enabled" do
      before do
        allow(library_settings).to receive(:flaky_test_retries_enabled?).and_return(true)
      end

      it "enables retrying failed tests" do
        subject

        expect(component.retry_failed_tests_enabled).to be true
      end
    end

    context "when flaky test retries are disabled" do
      before do
        allow(library_settings).to receive(:flaky_test_retries_enabled?).and_return(false)
      end

      it "disables retrying failed tests" do
        subject

        expect(component.retry_failed_tests_enabled).to be false
      end
    end
  end

  describe "#retry_failed_tests_max_attempts" do
    subject { component.retry_failed_tests_max_attempts }

    it { is_expected.to eq(retry_failed_tests_max_attempts) }
  end

  describe "#retry_failed_tests_total_limit" do
    subject { component.retry_failed_tests_total_limit }

    it { is_expected.to eq(retry_failed_tests_total_limit) }
  end

  describe "#build_strategy" do
    subject { component.build_strategy(test_span) }

    let(:test_failed) { false }
    let(:test_span) { instance_double(Datadog::CI::Test, failed?: test_failed) }

    before do
      component.configure(library_settings)
    end

    context "when retry failed tests is enabled" do
      let(:library_settings) { instance_double(Datadog::CI::Remote::LibrarySettings, flaky_test_retries_enabled?: true) }

      context "when test span is failed" do
        let(:test_failed) { true }

        context "when failed tests retry limit is not reached" do
          let(:retry_failed_tests_total_limit) { 1 }

          it "creates RetryFailed strategy" do
            expect(subject).to be_a(Datadog::CI::TestRetries::Strategy::RetryFailed)
            expect(subject.max_attempts).to eq(retry_failed_tests_max_attempts)
          end
        end

        context "when failed tests retry limit is reached" do
          let(:retry_failed_tests_total_limit) { 1 }

          before do
            component.build_strategy(test_span)
          end

          it { is_expected.to be_a(Datadog::CI::TestRetries::Strategy::NoRetry) }
        end

        context "when failed tests retry limit is reached with multithreading test runner" do
          let(:threads_count) { 10 }
          let(:retry_failed_tests_total_limit) { threads_count }

          before do
            threads = (1..threads_count).map do
              Thread.new { component.build_strategy(test_span) }
            end

            threads.each(&:join)
          end

          it "correctly exhausts failed tests limit" do
            is_expected.to be_a(Datadog::CI::TestRetries::Strategy::NoRetry)
          end
        end
      end

      context "when test span is passed" do
        let(:test_failed) { false }

        it { is_expected.to be_a(Datadog::CI::TestRetries::Strategy::NoRetry) }
      end
    end

    context "when retry failed tests is disabled" do
      let(:library_settings) { instance_double(Datadog::CI::Remote::LibrarySettings, flaky_test_retries_enabled?: false) }

      it { is_expected.to be_a(Datadog::CI::TestRetries::Strategy::NoRetry) }
    end
  end

  describe "#with_retries" do
    let(:test_failed) { false }
    let(:test_span) { instance_double(Datadog::CI::Test, failed?: test_failed, passed?: false, set_tag: true) }

    subject(:runs_count) do
      runs_count = 0
      component.with_retries do |test_finished_callback|
        runs_count += 1
        test_finished_callback.call(test_span)
      end

      runs_count
    end

    before do
      component.configure(library_settings)
    end

    context "when no retries strategy is used" do
      let(:library_settings) { instance_double(Datadog::CI::Remote::LibrarySettings, flaky_test_retries_enabled?: false) }

      it { is_expected.to eq(1) }
    end

    context "when retried failed tests strategy is used" do
      let(:library_settings) { instance_double(Datadog::CI::Remote::LibrarySettings, flaky_test_retries_enabled?: true) }

      context "when test span is failed" do
        let(:test_failed) { true }
        let(:retry_failed_tests_max_attempts) { 4 }

        it { is_expected.to eq(retry_failed_tests_max_attempts + 1) }
      end

      context "when test span is passed" do
        let(:test_failed) { false }

        it { is_expected.to eq(1) }
      end
    end
  end
end
