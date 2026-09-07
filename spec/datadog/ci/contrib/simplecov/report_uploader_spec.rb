# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/contrib/simplecov/report_uploader"

RSpec.describe Datadog::CI::Contrib::Simplecov::ReportUploader do
  describe ".included" do
    let(:base_class) do
      Class.new do
        class << self
          def process_result(*)
            0
          end
        end
      end
    end

    before do
      base_class.include(described_class)
    end

    describe "#process_result" do
      let(:coverage_path) { Dir.mktmpdir }
      let(:coverage_file) { File.join(coverage_path, ".resultset.json") }
      let(:coverage_data) { '{"test_suite":{"coverage":{"file.rb":[1,2,null]}}}' }
      let(:code_coverage) { instance_double(Datadog::CI::CodeCoverage::Component, enabled: code_coverage_enabled, upload: nil) }
      let(:code_coverage_enabled) { true }
      let(:components) { double(:components, code_coverage: code_coverage) }
      let(:simplecov_config) { {enabled: simplecov_enabled} }
      let(:simplecov_enabled) { true }

      before do
        SimpleCov.coverage_dir(coverage_path)
        File.write(coverage_file, coverage_data)

        allow(Datadog.configuration).to receive(:ci).and_return(double(:ci, :[] => simplecov_config))
        allow(Datadog).to receive(:send).with(:components).and_return(components)
      end

      around do |example|
        original_coverage_dir = SimpleCov.coverage_dir

        example.run
      ensure
        SimpleCov.coverage_dir(original_coverage_dir)
        FileUtils.rm_rf(coverage_path)
      end

      it "calls original process_result and returns its exit status" do
        expect(base_class.process_result(:result)).to eq(0)
      end

      it "uploads coverage report with correct parameters" do
        expect(code_coverage).to receive(:upload).with(
          serialized_report: coverage_data,
          format: Datadog::CI::Contrib::Simplecov::Ext::COVERAGE_FORMAT
        )

        base_class.process_result(:result)
      end

      context "when coverage file does not exist" do
        before do
          FileUtils.rm_f(coverage_file)
        end

        it "does not upload coverage report" do
          expect(code_coverage).not_to receive(:upload)

          base_class.process_result(:result)
        end

        it "returns the original result" do
          expect(base_class.process_result(:result)).to eq(0)
        end
      end

      context "when datadog simplecov integration is disabled" do
        let(:simplecov_enabled) { false }

        it "does not upload coverage report" do
          expect(code_coverage).not_to receive(:upload)

          base_class.process_result(:result)
        end
      end

      context "when code_coverage component is disabled" do
        let(:code_coverage_enabled) { false }

        it "does not upload coverage report" do
          expect(code_coverage).not_to receive(:upload)

          base_class.process_result(:result)
        end
      end

      context "when upload raises an error" do
        before do
          allow(code_coverage).to receive(:upload).and_raise(StandardError, "upload failed")
        end

        it "logs the error and continues" do
          expect(Datadog.logger).to receive(:warn).with("Failed to upload coverage report: upload failed")

          expect { base_class.process_result(:result) }.not_to raise_error
        end

        it "returns the original result" do
          allow(Datadog.logger).to receive(:warn)

          expect(base_class.process_result(:result)).to eq(0)
        end
      end

      context "when SimpleCov reports a coverage failure" do
        let(:base_class) do
          Class.new do
            class << self
              def process_result(*)
                1
              end
            end
          end
        end

        before do
          base_class.include(described_class)
        end

        it "does not upload the coverage report" do
          expect(code_coverage).not_to receive(:upload)

          expect(base_class.process_result(:result)).to eq(1)
        end
      end

      context "when SimpleCov has no result" do
        let(:base_class) do
          Class.new do
            class << self
              def process_result(*)
                nil
              end
            end
          end
        end

        before do
          base_class.include(described_class)
        end

        it "does not upload the coverage report and preserves the nil result" do
          expect(code_coverage).not_to receive(:upload)

          expect(base_class.process_result(:result)).to be_nil
        end
      end

      context "when original process_result accepts multiple arguments" do
        let(:base_class) do
          Class.new do
            class << self
              def process_result(arg1, arg2)
                arg1 + arg2
              end
            end
          end
        end

        before do
          base_class.include(described_class)
        end

        it "passes arguments correctly" do
          expect(code_coverage).to receive(:upload)

          expect(base_class.process_result(0, 0)).to eq(0)
        end
      end
    end
  end
end
