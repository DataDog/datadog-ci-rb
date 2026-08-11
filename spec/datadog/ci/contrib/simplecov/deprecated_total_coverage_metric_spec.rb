# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/contrib/simplecov/result_extractor"
require_relative "../../../../../lib/datadog/ci/test_tracing/deprecated_total_coverage_metric"

RSpec.describe Datadog::CI::TestTracing::DeprecatedTotalCoverageMetric do
  describe ".extract_lines_pct" do
    subject(:extract_lines_pct) { described_class.extract_lines_pct(test_session) }

    let(:test_session) { instance_double(Datadog::CI::TestSession, set_tag: true) }
    let(:simplecov_config) { {enabled: true} }

    before do
      allow(Datadog.configuration).to receive(:ci).and_return(double(:ci, :[] => simplecov_config))
    end

    context "when SimpleCov is not loaded" do
      before do
        hide_const("SimpleCov")
      end

      it "does not set the code coverage tag" do
        extract_lines_pct

        expect(test_session).not_to have_received(:set_tag)
      end
    end

    context "when SimpleCov is not running" do
      before do
        allow(described_class).to receive(:simplecov_running?).and_return(false)
      end

      it "does not set the code coverage tag" do
        extract_lines_pct

        expect(test_session).not_to have_received(:set_tag)
      end
    end

    context "when SimpleCov is running and patched" do
      before do
        SimpleCov.include(Datadog::CI::Contrib::Simplecov::ResultExtractor)
      end

      it "uses the loaded SimpleCov version to set the code coverage tag" do
        expect(SimpleCov.running).to be(true) if SimpleCov.respond_to?(:running)
        expect(Coverage.running?).to be(true) unless SimpleCov.respond_to?(:running)

        extract_lines_pct

        expect(test_session).to have_received(:set_tag).with(
          Datadog::CI::Ext::Test::TAG_CODE_COVERAGE_LINES_PCT,
          be_between(0, 100)
        )
      end

      context "when the result is nil" do
        let(:simplecov_config) { {enabled: false} }

        it "does not set the code coverage tag" do
          extract_lines_pct

          expect(test_session).not_to have_received(:set_tag)
        end
      end

      context "when SimpleCov extraction raises an error" do
        let(:simplecov_with_broken_api) do
          Module.new do
            def self.running
              true
            end

            def self.__dd_peek_result
              raise NoMethodError, "upstream API changed"
            end
          end
        end

        before do
          stub_const("SimpleCov", simplecov_with_broken_api)
          allow(Datadog.logger).to receive(:warn)
        end

        it "logs a warning without interrupting the test session" do
          expect { extract_lines_pct }.not_to raise_error

          expect(test_session).not_to have_received(:set_tag)
          expect(Datadog.logger).to have_received(:warn).with(
            "Failed to extract SimpleCov code coverage: NoMethodError: upstream API changed"
          )
        end
      end
    end
  end
end
