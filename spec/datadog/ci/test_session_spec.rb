# frozen_string_literal: true

RSpec.describe Datadog::CI::TestSession do
  let(:tracer_span) { Datadog::Tracing::SpanOperation.new("session") }
  let(:recorder) { spy("recorder") }

  before { allow_any_instance_of(described_class).to receive(:recorder).and_return(recorder) }
  subject(:ci_test_session) { described_class.new(tracer_span) }

  describe "#finish" do
    it "deactivates the test session" do
      ci_test_session.finish

      expect(recorder).to have_received(:deactivate_test_session)
    end
  end

  describe "#inheritable_tags" do
    subject(:inheritable_tags) { ci_test_session.inheritable_tags }

    before do
      Datadog::CI::Ext::Test::INHERITABLE_TAGS.each do |tag|
        tracer_span.set_tag(tag, "value for #{tag}")
      end
    end

    it "returns a hash of inheritable tags" do
      is_expected.to eq(
        Datadog::CI::Ext::Test::INHERITABLE_TAGS.each_with_object({}) do |tag, memo|
          memo[tag] = "value for #{tag}"
        end
      )
    end
  end

  describe "#name" do
    subject(:name) { ci_test_session.name }

    before do
      tracer_span.set_tag(Datadog::CI::Ext::Test::TAG_COMMAND, "test command")
    end

    it { is_expected.to eq("test command") }
  end

  describe "#skipping_tests?" do
    subject(:skipping_tests?) { ci_test_session.skipping_tests? }

    context "when not set" do
      it { is_expected.to be false }
    end

    context "when true" do
      before { tracer_span.set_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_ENABLED, true) }

      it { is_expected.to be true }
    end

    context "when false" do
      before { tracer_span.set_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_ENABLED, false) }

      it { is_expected.to be false }
    end
  end

  describe "#code_coverage?" do
    subject(:code_coverage?) { ci_test_session.code_coverage? }

    context "when not set" do
      it { is_expected.to be false }
    end

    context "when true" do
      before { tracer_span.set_tag(Datadog::CI::Ext::Test::TAG_CODE_COVERAGE_ENABLED, true) }

      it { is_expected.to be true }
    end

    context "when false" do
      before { tracer_span.set_tag(Datadog::CI::Ext::Test::TAG_CODE_COVERAGE_ENABLED, false) }

      it { is_expected.to be false }
    end
  end
end
