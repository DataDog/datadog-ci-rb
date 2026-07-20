# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/contrib/simplecov/result_extractor"

RSpec.describe Datadog::CI::Contrib::Simplecov::ResultExtractor do
  describe ".included" do
    let(:base_class) do
      Class.new do
        class << self
          def add_not_loaded_files(result)
            result
          end
        end
      end
    end

    before do
      base_class.include(described_class)
    end

    describe "#__dd_peek_result" do
      let(:simplecov_config) { {enabled: simplecov_enabled} }
      let(:simplecov_enabled) { true }
      let(:peeked_result) { {"file.rb" => [1, 0, nil]} }
      let(:coverage) { {"file.rb" => {"lines" => [1, 0, nil]}} }
      let(:result_class) { double(:result_class, new: simplecov_result) }
      let(:simplecov_result) { double(:simplecov_result) }

      before do
        allow(Datadog.configuration).to receive(:ci).and_return(double(:ci, :[] => simplecov_config))
        allow(::Coverage).to receive(:peek_result).and_return(peeked_result)

        stub_const("SimpleCov::ResultAdapter", double(:result_adapter, call: coverage))
        stub_const("SimpleCov::UselessResultsRemover", double(:useless_results_remover, call: coverage))
        stub_const("SimpleCov::Result", result_class)
      end

      context "when instrumentation is disabled" do
        let(:simplecov_enabled) { false }

        it "returns nil" do
          expect(base_class.__dd_peek_result).to be_nil
        end
      end

      context "when add_not_loaded_files returns a coverage hash (simplecov older than 1.0)" do
        it "builds the result from the coverage hash" do
          expect(base_class.__dd_peek_result).to be(simplecov_result)

          expect(result_class).to have_received(:new).with(coverage)
        end
      end

      context "when add_not_loaded_files returns a tuple (simplecov 1.0 or newer)" do
        let(:not_loaded_files) { Set.new(["not_loaded.rb"]) }

        before do
          allow(base_class).to receive(:add_not_loaded_files).and_return([coverage, not_loaded_files])
        end

        it "builds the result from the coverage hash and the not loaded files" do
          expect(base_class.__dd_peek_result).to be(simplecov_result)

          expect(result_class).to have_received(:new).with(coverage, not_loaded_files: not_loaded_files)
        end
      end
    end
  end
end
