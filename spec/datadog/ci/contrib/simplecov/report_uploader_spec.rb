# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/contrib/simplecov/report_uploader"

RSpec.describe Datadog::CI::Contrib::Simplecov::ReportUploader do
  describe ".included" do
    let(:base_class) do
      Class.new do
        class << self
          def process_results_and_report_error
            :original_result
          end
        end
      end
    end

    before do
      base_class.include(described_class)
    end

    describe "#process_results_and_report_error" do
      let(:coverage_path) { Dir.mktmpdir }
      let(:coverage_file) { File.join(coverage_path, ".resultset.json") }
      let(:coverage_data) { '{"test_suite":{"coverage":{"file.rb":[1,2,null]}}}' }
      let(:code_coverage) { instance_double(Datadog::CI::CodeCoverage::Component, enabled: code_coverage_enabled, upload: nil) }
      let(:code_coverage_enabled) { true }
      let(:components) { double(:components, code_coverage: code_coverage) }
      let(:simplecov_config) { {enabled: simplecov_enabled} }
      let(:simplecov_enabled) { true }
      let(:simplecov_module) { double(:simplecov, coverage_path: coverage_path) }

      before do
        File.write(coverage_file, coverage_data)

        allow(Datadog.configuration).to receive(:ci).and_return(double(:ci, :[] => simplecov_config))
        allow(Datadog).to receive(:send).with(:components).and_return(components)
        stub_const("SimpleCov", simplecov_module)
      end

      after do
        FileUtils.rm_rf(coverage_path)
      end

      it "calls original process_results_and_report_error and returns its result" do
        expect(base_class.process_results_and_report_error).to eq(:original_result)
      end

      it "uploads coverage report with correct parameters" do
        expect(code_coverage).to receive(:upload).with(
          serialized_report: coverage_data,
          format: Datadog::CI::Contrib::Simplecov::Ext::COVERAGE_FORMAT
        )

        base_class.process_results_and_report_error
      end

      context "when coverage file does not exist" do
        before do
          FileUtils.rm_f(coverage_file)
        end

        it "does not upload coverage report" do
          expect(code_coverage).not_to receive(:upload)

          base_class.process_results_and_report_error
        end

        it "returns the original result" do
          expect(base_class.process_results_and_report_error).to eq(:original_result)
        end
      end

      context "when datadog simplecov integration is disabled" do
        let(:simplecov_enabled) { false }

        it "does not upload coverage report" do
          expect(code_coverage).not_to receive(:upload)

          base_class.process_results_and_report_error
        end
      end

      context "when code_coverage component is disabled" do
        let(:code_coverage_enabled) { false }

        it "does not upload coverage report" do
          expect(code_coverage).not_to receive(:upload)

          base_class.process_results_and_report_error
        end
      end

      context "when upload raises an error" do
        before do
          allow(code_coverage).to receive(:upload).and_raise(StandardError, "upload failed")
        end

        it "logs the error and continues" do
          expect(Datadog.logger).to receive(:warn).with("Failed to upload coverage report: upload failed")

          expect { base_class.process_results_and_report_error }.not_to raise_error
        end

        it "returns the original result" do
          allow(Datadog.logger).to receive(:warn)

          expect(base_class.process_results_and_report_error).to eq(:original_result)
        end
      end

      context "when original process_results_and_report_error accepts arguments" do
        let(:base_class) do
          Class.new do
            class << self
              def process_results_and_report_error(arg1, arg2)
                [arg1, arg2]
              end
            end
          end
        end

        before do
          base_class.include(described_class)
        end

        it "passes arguments correctly" do
          expect(code_coverage).to receive(:upload)

          expect(base_class.process_results_and_report_error(:first, :second)).to eq([:first, :second])
        end
      end
    end
  end
end
