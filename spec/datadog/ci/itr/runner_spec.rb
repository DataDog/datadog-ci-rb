# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/itr/runner"

RSpec.describe Datadog::CI::ITR::Runner do
  let(:itr_enabled) { true }

  let(:writer) { spy("writer") }
  let(:git_worker) { spy("git_worker") }

  let(:tracer_span) { Datadog::Tracing::SpanOperation.new("session") }
  let(:test_session) { Datadog::CI::TestSession.new(tracer_span) }

  subject(:runner) { described_class.new(dd_env: "dd_env", coverage_writer: writer, enabled: itr_enabled) }

  before do
    allow(writer).to receive(:write)

    runner.configure(remote_configuration, test_session: test_session, git_tree_upload_worker: git_worker)
  end

  describe "#configure" do
    context "when remote configuration call failed" do
      let(:remote_configuration) { {"itr_enabled" => false} }

      it "configures the runner and test session" do
        expect(runner.enabled?).to be false
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be false
      end
    end

    context "when remote configuration call returned correct response" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false} }

      it "configures the runner" do
        expect(runner.enabled?).to be true
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be(!PlatformHelpers.jruby?) # code coverage is not supported in JRuby
      end

      it "sets test session tags" do
        expect(test_session.skipping_tests?).to be false
        expect(test_session.code_coverage?).to be true
        expect(test_session.get_tag(Datadog::CI::Ext::Test::TAG_ITR_TEST_SKIPPING_TYPE)).to eq(
          Datadog::CI::Ext::Test::ITR_TEST_SKIPPING_MODE
        )
      end
    end

    context "when remote configuration call returned correct response with strings instead of bools" do
      let(:remote_configuration) { {"itr_enabled" => "true", "code_coverage" => "true", "tests_skipping" => "false"} }

      it "configures the runner" do
        expect(runner.enabled?).to be true
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be(!PlatformHelpers.jruby?) # code coverage is not supported in JRuby
      end
    end

    context "when remote configuration call returns empty hash" do
      let(:remote_configuration) { {} }

      it "configures the runner" do
        expect(runner.enabled?).to be false
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be false
      end
    end
  end

  describe "#start_coverage" do
    let(:test_tracer_span) { Datadog::Tracing::SpanOperation.new("test") }
    let(:test_span) { Datadog::CI::Test.new(tracer_span) }

    context "when code coverage is disabled" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => false, "tests_skipping" => false} }

      it "does not start coverage" do
        expect(runner).not_to receive(:coverage_collector)

        runner.start_coverage
        expect(runner.stop_coverage(test_span)).to be_nil
      end
    end

    context "when ITR is disabled" do
      let(:remote_configuration) { {"itr_enabled" => false, "code_coverage" => false, "tests_skipping" => false} }

      it "does not start coverage" do
        expect(runner).not_to receive(:coverage_collector)

        runner.start_coverage
        expect(runner.stop_coverage(test_span)).to be_nil
      end
    end

    context "when code coverage is enabled" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false} }

      before do
        skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?
      end

      it "starts coverage" do
        expect(runner).to receive(:coverage_collector).twice.and_call_original

        runner.start_coverage
        expect(1 + 1).to eq(2)
        coverage_event = runner.stop_coverage(test_span)
        expect(coverage_event.coverage.size).to be > 0
      end
    end

    context "when JRuby and code coverage is enabled" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false} }

      before do
        skip("Skipped for CRuby") unless PlatformHelpers.jruby?
      end

      it "disables code coverage" do
        expect(runner).not_to receive(:coverage_collector)
        expect(runner.code_coverage?).to be(false)

        runner.start_coverage
        expect(runner.stop_coverage(test_span)).to be_nil
      end
    end
  end

  describe "#stop_coverage" do
    let(:test_tracer_span) { Datadog::Tracing::SpanOperation.new("test") }
    let(:test_span) { Datadog::CI::Test.new(tracer_span) }
    let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false} }

    before do
      skip("Code coverage is not supported in JRuby") if PlatformHelpers.jruby?

      expect(test_span).to receive(:id).and_return(1)
      expect(test_span).to receive(:test_suite_id).and_return(2)
      expect(test_span).to receive(:test_session_id).and_return(3)
    end

    it "creates coverage event and writes it" do
      runner.start_coverage
      expect(1 + 1).to eq(2)
      expect(runner.stop_coverage(test_span)).not_to be_nil

      expect(writer).to have_received(:write) do |event|
        expect(event.test_id).to eq("1")
        expect(event.test_suite_id).to eq("2")
        expect(event.test_session_id).to eq("3")

        expect(event.coverage.size).to be > 0
      end
    end
  end
end
