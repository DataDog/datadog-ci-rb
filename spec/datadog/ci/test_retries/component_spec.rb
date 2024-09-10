# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_retries/component"
require_relative "../../../../lib/datadog/ci/test_retries/unique_tests_client"

RSpec.describe Datadog::CI::TestRetries::Component do
  include_context "Telemetry spy"

  let(:library_settings) do
    instance_double(
      Datadog::CI::Remote::LibrarySettings,
      flaky_test_retries_enabled?: remote_flaky_test_retries_enabled,
      early_flake_detection_enabled?: remote_early_flake_detection_enabled,
      slow_test_retries: slow_test_retries,
      faulty_session_threshold: retry_new_tests_percentage_limit
    )
  end

  let(:retry_failed_tests_enabled) { true }
  let(:retry_failed_tests_max_attempts) { 1 }
  let(:retry_failed_tests_total_limit) { 12 }
  let(:retry_new_tests_enabled) { true }
  let(:retry_new_tests_percentage_limit) { 30 }
  let(:retry_new_tests_max_attempts) { 5 }

  let(:session_total_tests_count) { 30 }

  let(:remote_flaky_test_retries_enabled) { false }
  let(:remote_early_flake_detection_enabled) { false }

  let(:unique_tests_set) { Set.new(["test1", "test2"]) }
  let(:unique_tests_client) do
    instance_double(
      Datadog::CI::TestRetries::UniqueTestsClient,
      fetch_unique_tests: unique_tests_set
    )
  end

  let(:slow_test_retries) do
    instance_double(
      Datadog::CI::Remote::SlowTestRetries,
      max_attempts_for_duration: retry_new_tests_max_attempts
    )
  end

  let(:tracer_span) { Datadog::Tracing::SpanOperation.new("session") }
  let(:test_session) do
    Datadog::CI::TestSession.new(tracer_span).tap do |test_session|
      test_session.total_tests_count = session_total_tests_count
    end
  end

  subject(:component) do
    described_class.new(
      retry_failed_tests_enabled: retry_failed_tests_enabled,
      retry_failed_tests_max_attempts: retry_failed_tests_max_attempts,
      retry_failed_tests_total_limit: retry_failed_tests_total_limit,
      retry_new_tests_enabled: retry_new_tests_enabled,
      unique_tests_client: unique_tests_client
    )
  end

  describe "#configure" do
    subject { component.configure(library_settings, test_session) }

    context "when flaky test retries are enabled" do
      let(:remote_flaky_test_retries_enabled) { true }

      it "enables retrying failed tests" do
        subject

        expect(component.retry_failed_tests_enabled).to be true
      end
    end

    context "when flaky test retries are disabled" do
      let(:remote_flaky_test_retries_enabled) { false }

      it "disables retrying failed tests" do
        subject

        expect(component.retry_failed_tests_enabled).to be false
      end
    end

    context "when flaky test retries are disabled in local settings" do
      let(:retry_failed_tests_enabled) { false }
      let(:remote_flaky_test_retries_enabled) { true }

      it "disables retrying failed tests even if it's enabled remotely" do
        subject

        expect(component.retry_failed_tests_enabled).to be false
      end
    end

    context "when early flake detection is enabled" do
      let(:remote_early_flake_detection_enabled) { true }

      context "when unique tests set is empty" do
        let(:unique_tests_set) { Set.new }

        it "disables retrying new tests and adds fault reason to the test session" do
          subject

          expect(component.retry_new_tests_enabled).to be false
          expect(test_session.get_tag("test.early_flake.abort_reason")).to eq("faulty")
        end

        it_behaves_like "emits telemetry metric", :distribution, "early_flake_detection.response_tests", 0
      end

      context "when unique tests set is not empty" do
        it "enables retrying new tests" do
          subject

          expect(component.retry_new_tests_enabled).to be true
          expect(component.retry_new_tests_duration_thresholds.max_attempts_for_duration(1.2)).to eq(retry_new_tests_max_attempts)
          # 30% of 30 tests = 9
          expect(component.retry_new_tests_total_limit).to eq(9)
        end

        it_behaves_like "emits telemetry metric", :distribution, "early_flake_detection.response_tests", 2
      end
    end

    context "when early flake detection is disabled" do
      let(:remote_early_flake_detection_enabled) { false }

      it "disables retrying new tests" do
        subject

        expect(component.retry_new_tests_enabled).to be false
      end
    end

    context "when early flake detection is disabled in local settings" do
      let(:retry_new_tests_enabled) { false }
      let(:remote_early_flake_detection_enabled) { true }

      it "disables retrying new tests even if it's enabled remotely" do
        subject

        expect(component.retry_new_tests_enabled).to be false
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
    let(:test_span) { instance_double(Datadog::CI::Test, failed?: test_failed, name: "test", test_suite_name: "suite") }

    before do
      component.configure(library_settings, test_session)
    end

    context "when retry failed tests is enabled" do
      let(:remote_flaky_test_retries_enabled) { true }

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
      it { is_expected.to be_a(Datadog::CI::TestRetries::Strategy::NoRetry) }
    end
  end

  describe "#with_retries" do
    include_context "CI mode activated" do
      let(:flaky_test_retries_enabled) { true }
    end

    let(:component) do
      Datadog.send(:components).test_retries
    end

    let(:tracer_span) do
      instance_double(Datadog::Tracing::SpanOperation, duration: 1.2, set_tag: true)
    end
    let(:test_span) do
      instance_double(
        Datadog::CI::Test,
        failed?: test_failed,
        passed?: !test_failed,
        set_tag: true,
        get_tag: true,
        skipped?: false,
        type: "test",
        name: "mytest",
        test_suite_name: "mysuite"
      )
    end
    let(:test_failed) { false }

    subject(:runs_count) do
      runs_count = 0
      component.with_retries do
        runs_count += 1

        # run callbacks manually
        Datadog.send(:components).test_visibility.send(:on_test_finished, test_span)
        Datadog.send(:components).test_visibility.send(:on_after_test_span_finished, tracer_span)
      end

      runs_count
    end

    before do
      component.configure(library_settings, test_session)
    end

    context "when no retries strategy is used" do
      it { is_expected.to eq(1) }
    end

    context "when retry failed tests strategy is used" do
      let(:remote_flaky_test_retries_enabled) { true }

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

    context "when retry new test strategy is used" do
      let(:remote_early_flake_detection_enabled) { true }
      let(:unique_tests_set) { Set.new(["mysuite.mytest2."]) }

      it { is_expected.to eq(11) }

      context "when test duration increases" do
        let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, set_tag: true) }
        before do
          allow(tracer_span).to receive(:duration).and_return(5.1, 10.1, 30.1, 600.1)
        end

        # 5.1s (5 retries) -> 10.1s (3 retries) -> 30.1s (2 retries) -> done => 3 executions in total
        it { is_expected.to eq(3) }
      end
    end
  end
end
