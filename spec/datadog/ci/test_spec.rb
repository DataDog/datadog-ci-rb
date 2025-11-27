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
end
