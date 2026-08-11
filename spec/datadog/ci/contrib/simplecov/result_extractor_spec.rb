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
        context "when SimpleCov exposes the new unloaded file injection API" do
          let(:tracked_glob) { "lib/**/*.rb" }
          let(:tracked_paths) { [File.expand_path("../../../../../lib/datadog/ci.rb", __dir__)] }
          let(:simplecov_with_new_api) do
            Class.new do
              class << self
                attr_accessor :injected_coverage, :injected_paths

                def tracked_files
                  "lib/**/*.rb"
                end

                def cover_globs
                  []
                end

                def root
                  ::SimpleCov.root
                end

                def inject_unloaded_files(coverage, paths)
                  self.injected_coverage = coverage
                  self.injected_paths = paths
                  [coverage, Set.new(paths)]
                end
              end
            end
          end

          before do
            stub_const("SimpleCov::UnloadedFileInjector", double(:unloaded_file_injector))
            allow(SimpleCov::UnloadedFileInjector).to receive(:discover).and_return(tracked_paths)
            simplecov_with_new_api.include(described_class)
          end

          it "discovers tracked paths and injects unloaded files through the public API" do
            result = simplecov_with_new_api.__dd_peek_result

            expect(result).to be_a(SimpleCov::Result)
            expect(SimpleCov::UnloadedFileInjector).to have_received(:discover).with(
              [tracked_glob],
              root: SimpleCov.root
            )
            expect(simplecov_with_new_api.injected_coverage).to be_a(Hash)
            expect(simplecov_with_new_api.injected_paths).to eq(tracked_paths)
          end
        end

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
