# frozen_string_literal: true

RSpec.describe Datadog::CI::Test do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true) }
  let(:recorder) { spy("recorder") }
  subject(:ci_test) { described_class.new(tracer_span) }

  before { allow_any_instance_of(described_class).to receive(:recorder).and_return(recorder) }

  describe "#name" do
    subject(:name) { ci_test.name }

    before { allow(ci_test).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_NAME).and_return("test name") }

    it { is_expected.to eq("test name") }
  end

  describe "#finish" do
    it "deactivates the test" do
      ci_test.finish
      expect(recorder).to have_received(:deactivate_test)
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
    before { allow(ci_test).to receive(:test_suite).and_return(test_suite) }

    context "when test suite is set" do
      let(:test_suite) { instance_double(Datadog::CI::TestSuite, record_test_result: true) }

      it "records the test result in the test suite" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "pass")
        ci_test.passed!

        expect(test_suite).to have_received(:record_test_result).with("pass")
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
    before { allow(ci_test).to receive(:test_suite).and_return(test_suite) }

    context "when test suite is set" do
      let(:test_suite) { instance_double(Datadog::CI::TestSuite, record_test_result: true) }

      it "records the test result in the test suite" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "skip")

        ci_test.skipped!

        expect(test_suite).to have_received(:record_test_result).with("skip")
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
    before { allow(ci_test).to receive(:test_suite).and_return(test_suite) }

    context "when test suite is set" do
      let(:test_suite) { instance_double(Datadog::CI::TestSuite, record_test_result: true) }

      it "records the test result in the test suite" do
        expect(tracer_span).to receive(:set_tag).with("test.status", "fail")
        expect(tracer_span).to receive(:status=).with(1)

        ci_test.failed!

        expect(test_suite).to have_received(:record_test_result).with("fail")
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
end
