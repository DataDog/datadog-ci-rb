# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/cli/cli"

RSpec.describe Datadog::CI::CLI do
  describe ".exec" do
    subject(:exec) { described_class.exec(action, args) }

    let(:args) { [] }

    context "when action is 'exec'" do
      let(:action) { "exec" }
      let(:args) { ["bundle", "exec", "rspec"] }

      it "executes the test command" do
        command = instance_double(Datadog::CI::CLI::Command::Exec)
        expect(Datadog::CI::CLI::Command::Exec).to receive(:new).with(args).and_return(command)
        expect(command).to receive(:exec)
        exec
      end
    end

    %w[skipped-tests skippable-tests skipped-tests-estimate skippable-tests-estimate].each do |removed_action|
      context "when action is '#{removed_action}'" do
        let(:action) { removed_action }

        it "reports that skippable percentage calculation moved to ddtest and exits unsuccessfully" do
          expect { exec }
            .to output("#{described_class::SKIPPABLE_PERCENTAGE_REMOVAL_MESSAGE}\n").to_stderr
            .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end
      end
    end

    context "when action is not recognised" do
      let(:action) { "not-recognised" }

      it "prints the usage information" do
        expect { exec }.to output(<<~USAGE).to_stdout
          Usage: bundle exec ddcirb [command] [options]. Available commands:
            exec YOUR_TEST_COMMAND - automatically instruments your test command with Datadog and executes it
        USAGE
      end
    end
  end
end
