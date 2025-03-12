# frozen_string_literal: true

RSpec.describe Datadog::CI::TestSession do
  let(:tracer_span) { Datadog::Tracing::SpanOperation.new("session") }
  let(:test_visibility) { spy("test_visibility", logical_test_session_name: "my_test_session") }

  before { allow_any_instance_of(described_class).to receive(:test_visibility).and_return(test_visibility) }
  subject(:ci_test_session) { described_class.new(tracer_span) }

  describe "#finish" do
    it "deactivates the test session" do
      ci_test_session.finish

      expect(test_visibility).to have_received(:deactivate_test_session)
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

    it { is_expected.to eq("my_test_session") }
  end

  describe "#test_command" do
    subject(:test_command) { ci_test_session.test_command }

    before do
      tracer_span.set_tag(Datadog::CI::Ext::Test::TAG_COMMAND, "test command")
    end

    it { is_expected.to eq("test command") }
  end

  describe "#ci_provider" do
    subject(:ci_provider) { ci_test_session.ci_provider }

    before do
      tracer_span.set_tag(Datadog::CI::Ext::Environment::TAG_PROVIDER_NAME, "ci provider")
    end

    it { is_expected.to eq("ci provider") }
  end

  describe "#ci_job_name" do
    subject(:ci_job_name) { ci_test_session.ci_job_name }

    before do
      tracer_span.set_tag(Datadog::CI::Ext::Environment::TAG_JOB_NAME, "ci job name")
    end

    it { is_expected.to eq("ci job name") }
  end

  describe "#git_commit_message" do
    subject(:git_commit_message) { ci_test_session.git_commit_message }

    before do
      tracer_span.set_tag(Datadog::CI::Ext::Git::TAG_COMMIT_MESSAGE, "Test commit message")
    end

    it { is_expected.to eq("Test commit message") }
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
