# frozen_string_literal: true

RSpec.describe Datadog::CI::Test do
  include_context "Telemetry spy"

  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true) }
  let(:test_visibility) { spy("test_visibility") }

  subject(:ci_test) { described_class.new(tracer_span) }

  before { allow_any_instance_of(described_class).to receive(:test_visibility).and_return(test_visibility) }

  describe "#name" do
    subject(:name) { ci_test.name }

    before { allow(ci_test).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_NAME).and_return("test name") }

    it { is_expected.to eq("test name") }
  end

  describe "#finish" do
    before do
      allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_IS_RETRY).and_return(is_retry)
      allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_RETRY_REASON).and_return(retry_reason)
    end

    let(:is_retry) { nil }
    let(:retry_reason) { nil }

    it "deactivates the test" do
      ci_test.finish
      expect(test_visibility).to have_received(:deactivate_test)
    end

    context "when test is a retry" do
      let(:is_retry) { "true" }

      context "and retry reason is not set" do
        it "sets retry reason to external" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_RETRY_REASON,
            Datadog::CI::Ext::Test::RetryReason::RETRY_EXTERNAL
          )

          ci_test.finish
        end
      end

      context "and retry reason is already set" do
        let(:retry_reason) { "some_reason" }

        it "does not set retry reason" do
          expect(tracer_span).not_to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_RETRY_REASON,
            anything
          )

          ci_test.finish
        end
      end
    end

    context "when test is not a retry" do
      let(:is_retry) { nil }

      it "does not set retry reason" do
        expect(tracer_span).not_to receive(:set_tag).with(
          Datadog::CI::Ext::Test::TAG_RETRY_REASON,
          anything
        )

        ci_test.finish
      end
    end
  end

  describe "#test_suite_id" do
    subject(:test_suite_id) { ci_test.test_suite_id }

    before do
      allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID).and_return("test suite id")
    end

    it { is_expected.to eq("test suite id") }
  end

  describe "#test_suite_name" do
    subject(:test_suite_name) { ci_test.test_suite_name }

    before do
      allow(tracer_span).to(
        receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_SUITE).and_return("test suite name")
      )
    end

    it { is_expected.to eq("test suite name") }
  end

  describe "#test_suite" do
    subject(:test_suite) { ci_test.test_suite }

    context "when test suite name is set" do
      before do
        allow(ci_test).to receive(:test_suite_name).and_return("test suite name")
        allow(Datadog::CI).to receive(:active_test_suite).with("test suite name").and_return("test suite")
      end

      it { is_expected.to eq("test suite") }
    end

    context "when test suite name is not set" do
      before { allow(ci_test).to receive(:test_suite_name).and_return(nil) }

      it { is_expected.to be_nil }
    end
  end

  describe "#test_module_id" do
    subject(:test_module_id) { ci_test.test_module_id }

    before do
      allow(tracer_span).to(
        receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_TEST_MODULE_ID).and_return("test module id")
      )
    end

    it { is_expected.to eq("test module id") }
  end

  describe "#test_module_name" do
    subject(:test_module_name) { ci_test.test_module_name }

    before do
      allow(tracer_span).to(
        receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_MODULE).and_return("test module name")
      )
    end

    it { is_expected.to eq("test module name") }
  end

  describe "#test_session_id" do
    subject(:test_session_id) { ci_test.test_session_id }

    before do
      allow(tracer_span).to(
        receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID).and_return("test session id")
      )
    end

    it { is_expected.to eq("test session id") }
  end

  describe "#start_line" do
    subject(:start_line) { ci_test.start_line }

    context "when start line tag is set" do
      before do
        allow(tracer_span).to(
          receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_SOURCE_START).and_return("42")
        )
      end

      it { is_expected.to eq(42) }
    end

    context "when start line tag is not set" do
      before { allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_SOURCE_START).and_return(nil) }

      it { is_expected.to be_nil }
    end
  end

  describe "#end_line" do
    subject(:end_line) { ci_test.end_line }

    context "when end line tag is set" do
      before do
        allow(tracer_span).to(
          receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_SOURCE_END).and_return("100")
        )
      end

      it { is_expected.to eq(100) }
    end

    context "when end line tag is not set" do
      before { allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_SOURCE_END).and_return(nil) }

      it { is_expected.to be_nil }
    end
  end

  describe "#source_file" do
    subject(:source_file) { ci_test.source_file }

    before do
      allow(tracer_span).to(
        receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_SOURCE_FILE).and_return("foo/bar.rb")
      )
    end

    it { is_expected.to eq("foo/bar.rb") }
  end

  describe "#skipped_by_test_impact_analysis?" do
    subject(:skipped_by_itr) { ci_test.skipped_by_test_impact_analysis? }

    context "when tag is set" do
      before do
        allow(tracer_span).to(
          receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_ITR_SKIPPED_BY_ITR).and_return("true")
        )
      end

      it { is_expected.to be true }
    end

    context "when tag is not set" do
      before { allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_ITR_SKIPPED_BY_ITR).and_return(nil) }

      it { is_expected.to be false }
    end
  end

  describe "#retry_reason" do
    subject(:retry_reason) { ci_test.retry_reason }

    context "when retry reason tag is set" do
      before do
        allow(tracer_span).to(
          receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_RETRY_REASON).and_return("test_retry_reason")
        )
      end

      it { is_expected.to eq("test_retry_reason") }
    end

    context "when retry reason tag is not set" do
      before { allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_RETRY_REASON).and_return(nil) }

      it { is_expected.to be_nil }
    end
  end

  describe "#itr_unskippable!" do
    subject { ci_test.itr_unskippable! }

    context "when test is not skipped by ITR" do
      before do
        allow(ci_test).to receive(:skipped_by_test_impact_analysis?).and_return(false)
        expect(tracer_span).to receive(:set_tag).with(Datadog::CI::Ext::Test::TAG_ITR_UNSKIPPABLE, "true")
      end

      it "sets unskippable tag" do
        subject
      end

      it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_ITR_UNSKIPPABLE, 1
    end

    context "when test is skipped by ITR" do
      before do
        allow(ci_test).to receive(:skipped_by_test_impact_analysis?).and_return(true)
        expect(tracer_span).to receive(:set_tag).with(Datadog::CI::Ext::Test::TAG_ITR_UNSKIPPABLE, "true")
        expect(tracer_span).to receive(:clear_tag).with(Datadog::CI::Ext::Test::TAG_ITR_SKIPPED_BY_ITR)
        expect(tracer_span).to receive(:set_tag).with(Datadog::CI::Ext::Test::TAG_ITR_FORCED_RUN, "true")
      end

      it "sets unskippable tag, removes skipped by ITR tag, and sets forced run tag" do
        subject
      end

      it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_ITR_UNSKIPPABLE, 1
      it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_ITR_FORCED_RUN, 1
    end
  end

  describe "#set_parameters" do
    let(:parameters) { {"foo" => "bar", "baz" => "qux"} }

    it "sets the parameters" do
      expect(tracer_span).to receive(:set_tag).with(
        "test.parameters", JSON.generate({arguments: parameters, metadata: {}})
      )

      ci_test.set_parameters(parameters)
    end
  end

  describe "#passed!" do
    before do
      allow(ci_test).to receive(:test_suite).and_return(test_suite)
      allow(tracer_span).to receive(:get_tag).with("test.name").and_return("test name")
      allow(tracer_span).to receive(:get_tag).with("test.suite").and_return("test suite name")
      allow(tracer_span).to receive(:get_tag).with("test.parameters").and_return(nil)
    end

    context "when test suite is set" do
      let(:test_suite) { instance_double(Datadog::CI::TestSuite, record_test_result: true) }
      let(:test_executed) { false }

      before do
        expect(test_suite).to receive(:test_executed?).with("test suite name.test name.").and_return(test_executed)
      end

      it "records the test result in the test suite" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "pass")

        ci_test.passed!

        expect(test_suite).to have_received(:record_test_result).with("test suite name.test name.", "pass")
      end

      context "and when test was already executed" do
        let(:test_executed) { true }

        it "marks the test as retried" do
          expect(tracer_span).to receive(:set_tag).with("test.is_retry", "true")
          expect(tracer_span).to receive(:set_tag).with("test.status", "pass")

          ci_test.passed!
        end
      end
    end

    context "when test suite is not set" do
      let(:test_suite) { nil }

      it "does not record the test result in the test suite" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "pass")

        ci_test.passed!
      end
    end
  end

  describe "#skipped!" do
    before do
      allow(ci_test).to receive(:test_suite).and_return(test_suite)
      allow(tracer_span).to receive(:get_tag).with("test.name").and_return("test name")
      allow(tracer_span).to receive(:get_tag).with("test.suite").and_return("test suite name")
      allow(tracer_span).to receive(:get_tag).with("test.parameters").and_return(nil)
    end

    context "when test suite is set" do
      let(:test_suite) { instance_double(Datadog::CI::TestSuite, record_test_result: true) }
      let(:test_executed) { false }

      before do
        expect(test_suite).to receive(:test_executed?).with("test suite name.test name.").and_return(test_executed)
      end

      it "records the test result in the test suite" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "skip")

        ci_test.skipped!

        expect(test_suite).to have_received(:record_test_result).with("test suite name.test name.", "skip")
      end

      context "and when test was already executed" do
        let(:test_executed) { true }

        it "marks the test as retried" do
          expect(tracer_span).to receive(:set_tag).with("test.is_retry", "true")
          expect(tracer_span).to receive(:set_tag).with("test.status", "skip")

          ci_test.skipped!
        end
      end
    end

    context "when test suite is not set" do
      let(:test_suite) { nil }

      it "does not record the test result in the test suite" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "skip")

        ci_test.skipped!
      end
    end
  end

  describe "#failed!" do
    before do
      allow(ci_test).to receive(:test_suite).and_return(test_suite)

      allow(test_suite).to receive(:any_test_retry_passed?).and_return(false)

      allow(tracer_span).to receive(:get_tag).with("test.name").and_return("test name")
      allow(tracer_span).to receive(:get_tag).with("test.suite").and_return("test suite name")
      allow(tracer_span).to receive(:get_tag).with("test.parameters").and_return(nil)
      allow(tracer_span).to receive(:get_tag).with("test.test_management.is_quarantined").and_return(is_quarantined)
      allow(tracer_span).to receive(:get_tag).with("test.test_management.is_test_disabled").and_return(nil)
    end
    let(:is_quarantined) { nil }

    context "when test suite is set" do
      let(:test_suite) { instance_double(Datadog::CI::TestSuite, record_test_result: true) }
      let(:test_executed) { false }

      before do
        expect(test_suite).to receive(:test_executed?).with("test suite name.test name.").and_return(test_executed)
      end

      it "records the test result in the test suite" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "fail")
        expect(tracer_span).to receive(:status=).with(1)

        ci_test.failed!

        expect(test_suite).to have_received(:record_test_result).with("test suite name.test name.", "fail")
      end

      context "and when test is quarantined" do
        let(:is_quarantined) { "true" }

        it "records the test result as fail_ignored" do
          expect(tracer_span).to receive(:set_tag).with("test.status", "fail")
          expect(tracer_span).to receive(:status=).with(1)

          ci_test.failed!

          expect(test_suite).to have_received(:record_test_result).with("test suite name.test name.", "fail_ignored")
        end
      end

      context "and when test was already executed" do
        let(:test_executed) { true }

        it "marks the test as retried" do
          expect(tracer_span).to receive(:set_tag).with("test.is_retry", "true")
          expect(tracer_span).to receive(:set_tag).with("test.status", "fail")
          expect(tracer_span).to receive(:status=).with(1)

          ci_test.failed!
        end
      end
    end

    context "when test suite is not set" do
      let(:test_suite) { nil }

      it "does not record the test result in the test suite" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "fail")
        expect(tracer_span).to receive(:status=).with(1)

        ci_test.failed!
      end
    end
  end

  describe "#parameters" do
    let(:parameters) { JSON.generate({arguments: {"foo" => "bar", "baz" => "qux"}, metadata: {}}) }

    before do
      allow(tracer_span).to receive(:get_tag).with("test.parameters").and_return(parameters)
    end

    it "returns the parameters" do
      expect(ci_test.parameters).to eq(parameters)
    end
  end

  describe "#is_retry?" do
    subject(:is_retry) { ci_test.is_retry? }

    context "when tag is set" do
      before do
        allow(tracer_span).to(
          receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_IS_RETRY).and_return("true")
        )
      end

      it { is_expected.to be true }
    end

    context "when tag is not set" do
      before { allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_IS_RETRY).and_return(nil) }

      it { is_expected.to be false }
    end
  end

  describe "#quarantined?" do
    subject(:quarantined) { ci_test.quarantined? }

    context "when tag is set" do
      before do
        allow(tracer_span).to(
          receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_IS_QUARANTINED).and_return("true")
        )
      end

      it { is_expected.to be true }
    end

    context "when tag is not set" do
      before { allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_IS_QUARANTINED).and_return(nil) }

      it { is_expected.to be false }
    end
  end

  describe "#disabled?" do
    subject(:disabled) { ci_test.disabled? }

    context "when tag is set" do
      before do
        allow(tracer_span).to(
          receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_IS_TEST_DISABLED).and_return("true")
        )
      end

      it { is_expected.to be true }
    end

    context "when tag is not set" do
      before { allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_IS_TEST_DISABLED).and_return(nil) }

      it { is_expected.to be false }
    end
  end

  describe "#should_ignore_failures?" do
    subject(:should_ignore_failures) { ci_test.should_ignore_failures? }

    context "when quarantined" do
      before do
        allow(ci_test).to(
          receive(:quarantined?).and_return(true)
        )
      end

      it { is_expected.to be true }
    end

    context "when disabled" do
      before do
        allow(ci_test).to(
          receive(:quarantined?).and_return(false)
        )
        allow(ci_test).to(
          receive(:disabled?).and_return(true)
        )
      end

      it { is_expected.to be true }
    end

    context "when any retry passed" do
      before do
        allow(ci_test).to(
          receive(:quarantined?).and_return(false)
        )
        allow(ci_test).to(
          receive(:disabled?).and_return(false)
        )
        allow(ci_test).to(
          receive(:any_retry_passed?).and_return(true)
        )
      end

      it { is_expected.to be true }
    end

    context "when neither is true" do
      before do
        allow(ci_test).to(
          receive(:quarantined?).and_return(false)
        )
        allow(ci_test).to(
          receive(:disabled?).and_return(false)
        )
        allow(ci_test).to(
          receive(:any_retry_passed?).and_return(false)
        )
      end

      it { is_expected.to be false }
    end
  end

  describe "#record_final_status" do
    subject(:record_final_status) { ci_test.record_final_status }

    before do
      allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_STATUS).and_return(status)
    end

    context "when status tag is missing" do
      let(:status) { nil }

      it "does not set final status tag" do
        expect(tracer_span).not_to receive(:set_tag).with(
          Datadog::CI::Ext::Test::TAG_FINAL_STATUS,
          anything
        )

        record_final_status
      end
    end

    context "when status is pass" do
      let(:status) { Datadog::CI::Ext::Test::Status::PASS }

      it "persists final status as pass" do
        expect(tracer_span).to receive(:set_tag).with(
          Datadog::CI::Ext::Test::TAG_FINAL_STATUS,
          Datadog::CI::Ext::Test::Status::PASS
        )

        record_final_status
      end
    end

    context "when status is skip" do
      let(:status) { Datadog::CI::Ext::Test::Status::SKIP }

      it "persists final status as skip" do
        expect(tracer_span).to receive(:set_tag).with(
          Datadog::CI::Ext::Test::TAG_FINAL_STATUS,
          Datadog::CI::Ext::Test::Status::SKIP
        )

        record_final_status
      end
    end

    context "when status is fail" do
      let(:status) { Datadog::CI::Ext::Test::Status::FAIL }

      before do
        allow(ci_test).to receive(:should_ignore_failures?).and_return(ignore_failures)
      end

      context "and failures should be ignored" do
        let(:ignore_failures) { true }

        it "stores final status as pass" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_FINAL_STATUS,
            Datadog::CI::Ext::Test::Status::PASS
          )

          record_final_status
        end
      end

      context "and failures should not be ignored" do
        let(:ignore_failures) { false }

        it "stores final status as fail" do
          expect(tracer_span).to receive(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_FINAL_STATUS,
            Datadog::CI::Ext::Test::Status::FAIL
          )

          record_final_status
        end
      end
    end
  end

  describe "#datadog_skip_reason" do
    subject(:datadog_skip_reason) { ci_test.datadog_skip_reason }

    context "when skipped by ITR" do
      before do
        allow(ci_test).to(
          receive(:skipped_by_test_impact_analysis?).and_return(true)
        )
      end

      it { is_expected.to eq(Datadog::CI::Ext::Test::SkipReason::TEST_IMPACT_ANALYSIS) }
    end

    context "when disabled" do
      before do
        allow(ci_test).to(
          receive(:skipped_by_test_impact_analysis?).and_return(false)
        )
        allow(ci_test).to(
          receive(:disabled?).and_return(true)
        )
      end

      it { is_expected.to eq(Datadog::CI::Ext::Test::SkipReason::TEST_MANAGEMENT_DISABLED) }
    end

    context "when neither is true" do
      before do
        allow(ci_test).to(
          receive(:skipped_by_test_impact_analysis?).and_return(false)
        )
        allow(ci_test).to(
          receive(:disabled?).and_return(false)
        )
        allow(ci_test).to(
          receive(:quarantined?).and_return(false)
        )
      end

      it { is_expected.to be_nil }
    end
  end

  describe "#should_skip?" do
    subject(:should_skip) { ci_test.should_skip? }

    context "when skipped by ITR" do
      before do
        allow(ci_test).to(
          receive(:skipped_by_test_impact_analysis?).and_return(true)
        )
      end

      it { is_expected.to be true }
    end

    context "when disabled" do
      before do
        allow(ci_test).to(
          receive(:skipped_by_test_impact_analysis?).and_return(false)
        )
        allow(ci_test).to(
          receive(:disabled?).and_return(true)
        )
        allow(ci_test).to(
          receive(:attempt_to_fix?).and_return(attempt_to_fix)
        )
      end
      let(:attempt_to_fix) { false }

      it { is_expected.to be true }

      context "and attempt to fix" do
        let(:attempt_to_fix) { true }

        it { is_expected.to be false }
      end
    end

    context "when neither is true" do
      before do
        allow(ci_test).to(
          receive(:skipped_by_test_impact_analysis?).and_return(false)
        )
        allow(ci_test).to(
          receive(:disabled?).and_return(false)
        )
      end

      it { is_expected.to be false }
    end
  end

  describe "#modified?" do
    subject(:modified) { ci_test.modified? }

    context "when tag is set to 'true'" do
      before do
        allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_TEST_IS_MODIFIED).and_return("true")
      end
      it { is_expected.to be true }
    end

    context "when tag is set to 'false'" do
      before do
        allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_TEST_IS_MODIFIED).and_return("false")
      end
      it { is_expected.to be false }
    end

    context "when tag is not set" do
      before do
        allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_TEST_IS_MODIFIED).and_return(nil)
      end
      it { is_expected.to be false }
    end
  end

  describe "#peek_duration" do
    include_context "CI mode activated"

    let(:test_name) { "peek duration spec" }
    let(:test_suite_name) { "peek duration suite" }
    let(:peek_duration_test_visibility) { Datadog.send(:components).test_visibility }

    before do
      # Remove the test_visibility stub for these tests since we need the real component
      allow_any_instance_of(described_class).to receive(:test_visibility).and_call_original

      @started_peek_duration_tests = []
    end

    after do
      @started_peek_duration_tests&.each do |test|
        next if test.tracer_span.finished?
        test.finish
      end
      allow(Time).to receive(:now).and_call_original
    end

    def start_peek_duration_test
      peek_duration_test_visibility.trace_test(test_name, test_suite_name).tap do |test|
        expect(test).to be_a(described_class)
        @started_peek_duration_tests << test
      end
    end

    def stub_time_now(*values)
      allow(Time).to receive(:now).and_return(*values)
    end

    context "while the test is running" do
      it "returns the elapsed seconds relative to the test start time" do
        real_test = start_peek_duration_test
        start_time = real_test.tracer_span.start_time
        future_time = start_time + 2.5

        stub_time_now(future_time)

        expect(real_test.peek_duration).to be_within(1e-9).of(2.5)
      end
    end

    context "when invoked multiple times" do
      it "uses the latest wall time on every call" do
        real_test = start_peek_duration_test
        start_time = real_test.tracer_span.start_time

        stub_time_now(start_time + 0.5, start_time + 1.25, start_time + 3.0)

        expect(real_test.peek_duration).to be_within(1e-9).of(0.5)
        expect(real_test.peek_duration).to be_within(1e-9).of(1.25)
        expect(real_test.peek_duration).to be_within(1e-9).of(3.0)
      end
    end

    context "after the test has finished" do
      it "relies on the recorded start time and the current wall time" do
        real_test = start_peek_duration_test
        real_test.finish

        finished_at = real_test.tracer_span.end_time
        later_time = finished_at + 4.2

        stub_time_now(later_time)

        expected_duration = later_time - real_test.tracer_span.start_time
        expect(real_test.peek_duration).to be_within(1e-9).of(expected_duration)
      end
    end
  end
end
