# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/cli/command/skippable_tests_percentage_estimate"

RSpec.describe Datadog::CI::CLI::Command::SkippableTestsPercentageEstimate do
  subject(:command) { described_class.new }

  describe "#exec" do
    subject(:exec) { command.exec }

    # inputs
    let(:verbose) { false }
    let(:spec_path) { "spec" }
    let(:argv) { [] }

    # outputs
    let(:failed) { false }
    let(:result) { "result" }
    let(:action) { double("action", call: result, failed: failed) }

    before do
      allow(::Datadog::CI::TestOptimisation::SkippablePercentage::Estimator).to receive(:new).with(
        verbose: verbose,
        spec_path: spec_path
      ).and_return(action)

      stub_const("ARGV", argv)
    end

    context "when no CLI options are given" do
      let(:argv) { [] }

      it "executes the action, validates it, and outputs the result" do
        expect { exec }.to output("result").to_stdout
      end
    end

    context "when file option is given" do
      let(:argv) { ["-f", "output.txt"] }

      it "writes the result to the file" do
        expect(File).to receive(:write).with("output.txt", "result")

        exec
      end
    end

    context "when verbose option is given" do
      let(:argv) { ["--verbose"] }
      let(:verbose) { true }

      it "passes the verbose option to the action" do
        expect { exec }.to output("result").to_stdout
      end
    end

    context "when spec-path option is given" do
      let(:argv) { ["--spec-path=spec/models"] }
      let(:spec_path) { "spec/models" }

      it "passes the spec-path option to the action" do
        expect { exec }.to output("result").to_stdout
      end
    end

    context "when the action fails" do
      let(:failed) { true }

      it "exits with status 1" do
        expect { exec }.to raise_error(SystemExit)
      end
    end
  end
end
