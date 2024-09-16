require_relative "../../../../../lib/datadog/ci/test_retries/strategy/retry_new"

RSpec.describe Datadog::CI::TestRetries::Strategy::RetryNew do
  include_context "Telemetry spy"

  let(:enabled) { true }

  let(:unique_tests_set) { Set.new(["test1", "test2"]) }
  let(:unique_tests_client) do
    instance_double(
      Datadog::CI::TestRetries::UniqueTestsClient,
      fetch_unique_tests: unique_tests_set
    )
  end

  let(:remote_early_flake_detection_enabled) { false }
  let(:percentage_limit) { 30 }
  let(:max_attempts) { 5 }

  let(:slow_test_retries) do
    instance_double(
      Datadog::CI::Remote::SlowTestRetries,
      max_attempts_for_duration: max_attempts
    )
  end

  let(:session_total_tests_count) { 30 }

  let(:library_settings) do
    instance_double(
      Datadog::CI::Remote::LibrarySettings,
      early_flake_detection_enabled?: remote_early_flake_detection_enabled,
      slow_test_retries: slow_test_retries,
      faulty_session_threshold: percentage_limit
    )
  end

  let(:tracer_span) { Datadog::Tracing::SpanOperation.new("session") }
  let(:test_session) do
    Datadog::CI::TestSession.new(tracer_span).tap do |test_session|
      test_session.total_tests_count = session_total_tests_count
    end
  end

  subject(:strategy) do
    described_class.new(
      enabled: enabled,
      unique_tests_client: unique_tests_client
    )
  end

  describe "#configure" do
    subject { strategy.configure(library_settings, test_session) }

    context "when early flake detection is enabled" do
      let(:remote_early_flake_detection_enabled) { true }

      context "when unique tests set is empty" do
        let(:unique_tests_set) { Set.new }

        it "disables retrying new tests and adds fault reason to the test session" do
          subject

          expect(strategy.enabled).to be false
          expect(test_session.get_tag("test.early_flake.abort_reason")).to eq("faulty")
        end

        it_behaves_like "emits telemetry metric", :distribution, "early_flake_detection.response_tests", 0
      end

      context "when unique tests set is not empty" do
        it "enables retrying new tests" do
          subject

          expect(strategy.enabled).to be true
          expect(strategy.max_attempts_thresholds.max_attempts_for_duration(1.2)).to eq(max_attempts)
          # 30% of 30 tests = 9
          expect(strategy.total_limit).to eq(9)
        end

        it_behaves_like "emits telemetry metric", :distribution, "early_flake_detection.response_tests", 2
      end
    end

    context "when early flake detection is disabled" do
      let(:remote_early_flake_detection_enabled) { false }

      it "disables retrying new tests" do
        subject

        expect(strategy.enabled).to be false
      end
    end

    context "when early flake detection is disabled in local settings" do
      let(:enabled) { false }
      let(:remote_early_flake_detection_enabled) { true }

      it "disables retrying new tests even if it's enabled remotely" do
        subject

        expect(strategy.enabled).to be false
      end
    end
  end
end
