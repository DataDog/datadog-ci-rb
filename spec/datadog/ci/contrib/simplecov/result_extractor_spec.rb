# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/contrib/simplecov/result_extractor"

RSpec.describe Datadog::CI::Contrib::Simplecov::ResultExtractor do
  describe "with SimpleCov 1.1 result processing APIs" do
    let(:base_class) do
      Class.new do
        class << self
          def tracked_file_paths
            Set.new(["loaded.rb", "not_loaded.rb"])
          end

          def inject_unloaded_files(result, tracked_files)
            [result.merge("not_loaded.rb" => {"lines" => [0]}), tracked_files]
          end
        end
      end
    end
    let(:simplecov_config) { {enabled: true} }
    let(:coverage) { {"loaded.rb" => {"lines" => [1]}} }
    let(:not_loaded_files) { Set.new(["not_loaded.rb"]) }
    let(:result_class) { class_double(SimpleCov::Result, new: simplecov_result) }
    let(:simplecov_result) { instance_double(SimpleCov::Result) }

    before do
      base_class.include(described_class)
      allow(Datadog.configuration).to receive(:ci).and_return(double(:ci, :[] => simplecov_config))
      allow(Coverage).to receive(:peek_result).and_return(coverage)
      allow(SimpleCov::UselessResultsRemover).to receive(:call).and_return(coverage)
      allow(SimpleCov::ResultAdapter).to receive(:call).and_return(coverage)
      stub_const("SimpleCov::Result", result_class)
    end

    it "builds a result with coverage for configured files that were not loaded" do
      expect(base_class.__dd_peek_result).to be(simplecov_result)

      expect(result_class).to have_received(:new).with(
        coverage.merge("not_loaded.rb" => {"lines" => [0]}),
        not_loaded_files: not_loaded_files,
        tracked_files: not_loaded_files
      )
    end
  end

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

        it "applies configured filters" do
          filtered_file = File.expand_path("../../../../../lib/datadog/ci.rb", __dir__)
          original_filters = SimpleCov.filters.dup
          filter_method = SimpleCov.respond_to?(:skip) ? :skip : :add_filter
          SimpleCov.public_send(filter_method, "lib/datadog/ci.rb")

          expect(SimpleCov.__dd_peek_result.filenames).not_to include(filtered_file)
        ensure
          SimpleCov.filters.replace(original_filters)
        end

        it "includes configured files that have not been loaded" do
          tracked_directory = Dir.mktmpdir("simplecov-", SimpleCov.root)
          tracked_file = File.join(tracked_directory, "not_loaded.rb")
          File.write(tracked_file, "# This file is deliberately not loaded.\n")

          if SimpleCov.respond_to?(:cover)
            original_cover_filters = SimpleCov.cover_filters.dup
            SimpleCov.cover(tracked_file.delete_prefix("#{SimpleCov.root}/"))
          else
            original_tracked_files = SimpleCov.tracked_files
            SimpleCov.track_files(tracked_file)
          end

          expect(SimpleCov.__dd_peek_result.filenames).to include(tracked_file)
        ensure
          if SimpleCov.respond_to?(:cover)
            SimpleCov.cover_filters.replace(original_cover_filters)
          else
            SimpleCov.track_files(original_tracked_files)
          end
          FileUtils.rm_rf(tracked_directory) if tracked_directory
        end
      end
    end
  end
end
