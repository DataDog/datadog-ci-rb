# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/itr/runner"

RSpec.describe Datadog::CI::ITR::Runner do
  let(:itr_enabled) { true }
  let(:tracer_span) { Datadog::Tracing::SpanOperation.new("session") }
  let(:test_session) { Datadog::CI::TestSession.new(tracer_span) }

  subject(:runner) { described_class.new(enabled: itr_enabled) }

  describe "#configure" do
    before do
      runner.configure(remote_configuration, test_session)
    end

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
        expect(runner.code_coverage?).to be(!PlatformHelpers.jruby? && true) # code coverage is not supported in JRuby
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
        expect(runner.code_coverage?).to be(!PlatformHelpers.jruby? && true) # code coverage is not supported in JRuby
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
    before do
      runner.configure(remote_configuration, test_session)
    end
    context "when code coverage is disabled" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => false, "tests_skipping" => false} }

      it "does not start coverage" do
        expect(runner).not_to receive(:coverage_collector)

        runner.start_coverage
        expect(runner.stop_coverage).to be_nil
      end
    end

    context "when ITR is disabled" do
      let(:remote_configuration) { {"itr_enabled" => false, "code_coverage" => false, "tests_skipping" => false} }

      it "does not start coverage" do
        expect(runner).not_to receive(:coverage_collector)

        runner.start_coverage
        expect(runner.stop_coverage).to be_nil
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
        coverage = runner.stop_coverage
        expect(coverage.size).to be > 0
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
        expect(runner.stop_coverage).to be_nil
      end
    end
  end
end
