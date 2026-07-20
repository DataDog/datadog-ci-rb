# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_tracing/deprecated_total_coverage_metric"

RSpec.describe Datadog::CI::TestTracing::DeprecatedTotalCoverageMetric do
  describe ".extract_lines_pct" do
    subject(:extract_lines_pct) { described_class.extract_lines_pct(test_session) }

    let(:test_session) { instance_double(Datadog::CI::TestSession, set_tag: true) }

    context "when SimpleCov is not loaded" do
      before do
        hide_const("SimpleCov")
      end

      it "does not set the code coverage tag" do
        extract_lines_pct

        expect(test_session).not_to have_received(:set_tag)
      end
    end

    context "when SimpleCov defines the running accessor (older than 1.0)" do
      let(:simplecov_module) { double(:simplecov, running: running) }

      before do
        stub_const("SimpleCov", simplecov_module)
      end

      context "when SimpleCov is not running" do
        let(:running) { false }

        it "does not set the code coverage tag" do
          extract_lines_pct

          expect(test_session).not_to have_received(:set_tag)
        end
      end

      context "when SimpleCov is running and patched" do
        let(:running) { true }
        let(:result) { double(:result, covered_percent: 85.5) }

        before do
          allow(simplecov_module).to receive(:__dd_peek_result).and_return(result)
        end

        it "sets the code coverage tag" do
          extract_lines_pct

          expect(test_session).to have_received(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_CODE_COVERAGE_LINES_PCT, 85.5
          )
        end
      end
    end

    context "when SimpleCov does not define the running accessor (1.0 or newer)" do
      let(:simplecov_module) { double(:simplecov) }

      before do
        stub_const("SimpleCov", simplecov_module)
        allow(::Coverage).to receive(:running?).and_return(coverage_running)
      end

      context "when Coverage is not running" do
        let(:coverage_running) { false }

        it "does not set the code coverage tag" do
          extract_lines_pct

          expect(test_session).not_to have_received(:set_tag)
        end
      end

      context "when Coverage is running and SimpleCov is patched" do
        let(:coverage_running) { true }
        let(:result) { double(:result, covered_percent: 90.0) }

        before do
          allow(simplecov_module).to receive(:__dd_peek_result).and_return(result)
        end

        it "sets the code coverage tag" do
          extract_lines_pct

          expect(test_session).to have_received(:set_tag).with(
            Datadog::CI::Ext::Test::TAG_CODE_COVERAGE_LINES_PCT, 90.0
          )
        end
      end

      context "when Coverage is running but the result is nil" do
        let(:coverage_running) { true }

        before do
          allow(simplecov_module).to receive(:__dd_peek_result).and_return(nil)
        end

        it "does not set the code coverage tag" do
          extract_lines_pct

          expect(test_session).not_to have_received(:set_tag)
        end
      end
    end
  end
end
