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
    it "deactivates the test" do
      ci_test.finish
      expect(test_visibility).to have_received(:deactivate_test)
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

  describe "#test_session_id" do
    subject(:test_session_id) { ci_test.test_session_id }

    before do
      allow(tracer_span).to(
        receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID).and_return("test session id")
      )
    end

    it { is_expected.to eq("test session id") }
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

  describe "#skipped_by_itr?" do
    subject(:skipped_by_itr) { ci_test.skipped_by_itr? }

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

  describe "#itr_unskippable!" do
    subject { ci_test.itr_unskippable! }

    context "when test is not skipped by ITR" do
      before do
        allow(ci_test).to receive(:skipped_by_itr?).and_return(false)
        expect(tracer_span).to receive(:set_tag).with(Datadog::CI::Ext::Test::TAG_ITR_UNSKIPPABLE, "true")
      end

      it "sets unskippable tag" do
        subject
      end

      it_behaves_like "emits telemetry metric", :inc, Datadog::CI::Ext::Telemetry::METRIC_ITR_UNSKIPPABLE, 1
    end

    context "when test is skipped by ITR" do
      before do
        allow(ci_test).to receive(:skipped_by_itr?).and_return(true)
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
      expect(tracer_span).to receive(:get_tag).with("test.name").and_return("test name")
      expect(tracer_span).to receive(:get_tag).with("test.suite").and_return("test suite name")
      expect(tracer_span).to receive(:get_tag).with("test.parameters").and_return(nil)
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
      expect(tracer_span).to receive(:get_tag).with("test.name").and_return("test name")
      expect(tracer_span).to receive(:get_tag).with("test.suite").and_return("test suite name")
      expect(tracer_span).to receive(:get_tag).with("test.parameters").and_return(nil)
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

      expect(tracer_span).to receive(:get_tag).with("test.name").and_return("test name")
      expect(tracer_span).to receive(:get_tag).with("test.suite").and_return("test suite name")
      expect(tracer_span).to receive(:get_tag).with("test.parameters").and_return(nil)
    end

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
end
