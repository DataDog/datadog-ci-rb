# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/cli/cli"

RSpec.describe Datadog::CI::CLI do
  describe ".exec" do
    subject(:exec) { described_class.exec(action) }

    context "when action is 'skippable-tests'" do
      let(:action) { "skippable-tests" }

      it "executes the skippable tests percentage command" do
        expect(Datadog::CI::CLI::Command::SkippableTestsPercentage).to receive(:new).and_call_original
        expect_any_instance_of(Datadog::CI::CLI::Command::SkippableTestsPercentage).to receive(:exec)

        exec
      end
    end

    context "when action is 'skippable-tests-estimate'" do
      let(:action) { "skippable-tests-estimate" }

      it "executes the skippable tests percentage estimate command" do
        expect(Datadog::CI::CLI::Command::SkippableTestsPercentageEstimate).to receive(:new).and_call_original
        expect_any_instance_of(Datadog::CI::CLI::Command::SkippableTestsPercentageEstimate).to receive(:exec)

        exec
      end
    end

    context "when action is not recognised" do
      let(:action) { "not-recognised" }

      it "prints the usage information" do
        expect { exec }.to output(<<~USAGE).to_stdout
          Usage: bundle exec ddcirb [command] [options]. Available commands:
            skippable-tests - calculates the exact percentage of skipped tests and prints it to stdout or file
            skippable-tests-estimate - estimates the percentage of skipped tests and prints it to stdout or file
            exec YOUR_TEST_COMMAND - automatically instruments your test command with Datadog and executes it
        USAGE
      end
    end
  end
end
