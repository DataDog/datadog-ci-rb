# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/contrib/simplecov/result_extractor"

RSpec.describe Datadog::CI::Contrib::Simplecov::ResultExtractor do
  describe ".included" do
    before do
      SimpleCov.include(described_class)
    end

    describe "#__dd_peek_result" do
      let(:simplecov_config) { {enabled: simplecov_enabled} }
      let(:simplecov_enabled) { true }

      before do
        allow(Datadog.configuration).to receive(:ci).and_return(double(:ci, :[] => simplecov_config))
      end

      context "when instrumentation is disabled" do
        let(:simplecov_enabled) { false }

        it "returns nil" do
          expect(SimpleCov.__dd_peek_result).to be_nil
        end
      end

      context "when instrumentation is enabled" do
        it "builds a result using the loaded SimpleCov version" do
          result = SimpleCov.__dd_peek_result

          expect(result).to be_a(SimpleCov::Result)
          expect(result.filenames).to include(File.expand_path("../../../../../lib/datadog/ci.rb", __dir__))
          expect(result.covered_percent).to be_between(0, 100)
        end
      end
    end
  end
end
