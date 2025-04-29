# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_retries/component"

RSpec.describe Datadog::CI::TestRetries::Component do
  include_context "Telemetry spy"

  let(:library_settings) do
    instance_double(
      Datadog::CI::Remote::LibrarySettings,
      flaky_test_retries_enabled?: remote_flaky_test_retries_enabled,
      early_flake_detection_enabled?: remote_early_flake_detection_enabled,
      known_tests_enabled?: remote_known_tests_enabled,
      slow_test_retries: slow_test_retries,
      faulty_session_threshold: retry_new_tests_percentage_limit,
      test_management_enabled?: remote_test_management_enabled,
      attempt_to_fix_retries_count: remote_attempt_to_fix_retries_count
    )
  end

  let(:retry_failed_tests_enabled) { true }
  let(:retry_failed_tests_max_attempts) { 1 }
  let(:retry_failed_tests_total_limit) { 12 }
  let(:retry_new_tests_enabled) { true }
  let(:retry_new_tests_percentage_limit) { 30 }
  let(:retry_new_tests_max_attempts) { 5 }
  let(:retry_flaky_fixed_tests_enabled) { true }
  let(:retry_flaky_fixed_tests_max_attempts) { 42 }

  let(:session_total_tests_count) { 30 }

  let(:remote_flaky_test_retries_enabled) { false }
  let(:remote_early_flake_detection_enabled) { false }
  let(:remote_known_tests_enabled) { true }
  let(:remote_test_management_enabled) { false }
  let(:remote_attempt_to_fix_retries_count) { 43 }

  let(:slow_test_retries) do
    instance_double(
      Datadog::CI::Remote::SlowTestRetries,
      max_attempts_for_duration: retry_new_tests_max_attempts
    )
  end

  let(:tracer_span) { Datadog::Tracing::SpanOperation.new("session") }
  let(:test_session) do
    Datadog::CI::TestSession.new(tracer_span).tap do |test_session|
      test_session.estimated_total_tests_count = session_total_tests_count
    end
  end

  subject(:component) do
    described_class.new(
      retry_failed_tests_enabled: retry_failed_tests_enabled,
      retry_failed_tests_max_attempts: retry_failed_tests_max_attempts,
      retry_failed_tests_total_limit: retry_failed_tests_total_limit,
      retry_new_tests_enabled: retry_new_tests_enabled,
      retry_flaky_fixed_tests_enabled: retry_flaky_fixed_tests_enabled,
      retry_flaky_fixed_tests_max_attempts: retry_flaky_fixed_tests_max_attempts
    )
  end

  describe "#build_driver" do
    subject { component.build_driver(test_span) }

    let(:test_failed) { false }
    let(:test_skipped) { false }
    let(:test_is_new) { false }
    let(:test_modified) { false }
    let(:test_attempt_to_fix) { false }

    let(:test_span) do
      instance_double(
        Datadog::CI::Test,
        name: "test",
        test_suite_name: "suite",
        failed?: test_failed,
        skipped?: test_skipped,
        is_new?: test_is_new,
        attempt_to_fix?: test_attempt_to_fix,
        modified?: test_modified,
        set_tag: nil
      )
    end

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
            expect(subject).to be_a(Datadog::CI::TestRetries::Driver::RetryFailed)
            expect(subject.max_attempts).to eq(retry_failed_tests_max_attempts)
          end
        end

        context "when failed tests retry limit is reached" do
          let(:retry_failed_tests_total_limit) { 1 }

          before do
            component.build_driver(test_span)
          end

          it { is_expected.to be_a(Datadog::CI::TestRetries::Driver::NoRetry) }
        end

        context "when failed tests retry limit is reached with multithreading test runner" do
          let(:threads_count) { 10 }
          let(:retry_failed_tests_total_limit) { threads_count }

          before do
            threads = (1..threads_count).map do
              Thread.new { component.build_driver(test_span) }
            end

            threads.each(&:join)
          end

          it "correctly exhausts failed tests limit" do
            is_expected.to be_a(Datadog::CI::TestRetries::Driver::NoRetry)
          end
        end
      end

      context "when test span is passed" do
        let(:test_failed) { false }

        it { is_expected.to be_a(Datadog::CI::TestRetries::Driver::NoRetry) }
      end
    end

    context "when retry new tests is enabled" do
      let(:remote_early_flake_detection_enabled) { true }

      context "when test is new" do
        let(:test_is_new) { true }

        it { is_expected.to be_a(Datadog::CI::TestRetries::Driver::RetryFlakeDetection) }

        context "when test is skipped" do
          let(:test_skipped) { true }

          it { is_expected.to be_a(Datadog::CI::TestRetries::Driver::NoRetry) }
        end

        context "when known tests are disabled" do
          let(:remote_known_tests_enabled) { false }

          it { is_expected.to be_a(Datadog::CI::TestRetries::Driver::NoRetry) }
        end
      end

      context "when test is modified" do
        let(:test_modified) { true }

        it { is_expected.to be_a(Datadog::CI::TestRetries::Driver::RetryFlakeDetection) }
      end

      context "when test is not new and not modified" do
        it { is_expected.to be_a(Datadog::CI::TestRetries::Driver::NoRetry) }
      end
    end

    context "when retry flaky fixed tests is enabled" do
      let(:remote_test_management_enabled) { true }

      context "when test is attempted to be fixed" do
        let(:test_attempt_to_fix) { true }

        it "uses RetryFlakyFixed strategy" do
          expect(subject).to be_a(Datadog::CI::TestRetries::Driver::RetryFlakyFixed)
          expect(subject.max_attempts).to eq(remote_attempt_to_fix_retries_count)
        end
      end

      context "when test is not attempted to be fixed" do
        it { is_expected.to be_a(Datadog::CI::TestRetries::Driver::NoRetry) }
      end
    end

    context "no retries are enabled" do
      it { is_expected.to be_a(Datadog::CI::TestRetries::Driver::NoRetry) }
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
        is_new?: test_is_new,
        set_tag: true,
        get_tag: true,
        skipped?: false,
        type: "test",
        name: "mytest",
        test_suite_name: "mysuite",
        attempt_to_fix?: test_attempt_to_fix,
        all_executions_failed?: false,
        all_executions_passed?: false
      )
    end

    let(:test_failed) { false }
    let(:test_is_new) { false }
    let(:test_attempt_to_fix) { false }

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
      let(:test_is_new) { true }

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

    context "when retry flaky fixed test strategy is used" do
      let(:remote_test_management_enabled) { true }
      let(:test_attempt_to_fix) { true }

      it { is_expected.to eq(remote_attempt_to_fix_retries_count + 1) }
    end
  end
end
