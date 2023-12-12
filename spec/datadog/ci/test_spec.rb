# frozen_string_literal: true

RSpec.describe Datadog::CI::Test do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true) }

  describe "#name" do
    subject(:name) { ci_test.name }
    let(:ci_test) { described_class.new(tracer_span) }

    before { allow(ci_test).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_NAME).and_return("test name") }

    it { is_expected.to eq("test name") }
  end

  describe "#finish" do
    subject(:ci_test) { described_class.new(tracer_span) }

    before { allow(Datadog::CI).to receive(:deactivate_test) }

    it "deactivates the test" do
      ci_test.finish
      expect(Datadog::CI).to have_received(:deactivate_test).with(ci_test)
    end
  end

  describe "#test_suite_id" do
    subject(:test_suite_id) { ci_test.test_suite_id }
    let(:ci_test) { described_class.new(tracer_span) }

    before do
      allow(tracer_span).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID).and_return("test suite id")
    end

    it { is_expected.to eq("test suite id") }
  end

  describe "#test_suite_name" do
    subject(:test_suite_name) { ci_test.test_suite_name }
    let(:ci_test) { described_class.new(tracer_span) }

    before do
      allow(tracer_span).to(
        receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_SUITE).and_return("test suite name")
      )
    end

    it { is_expected.to eq("test suite name") }
  end

  describe "#test_module_id" do
    subject(:test_module_id) { ci_test.test_module_id }
    let(:ci_test) { described_class.new(tracer_span) }

    before do
      allow(tracer_span).to(
        receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_TEST_MODULE_ID).and_return("test module id")
      )
    end

    it { is_expected.to eq("test module id") }
  end

  describe "#test_session_id" do
    subject(:test_session_id) { ci_test.test_session_id }
    let(:ci_test) { described_class.new(tracer_span) }

    before do
      allow(tracer_span).to(
        receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID).and_return("test session id")
      )
    end

    it { is_expected.to eq("test session id") }
  end
end
