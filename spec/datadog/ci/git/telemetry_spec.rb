# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/git/telemetry"
require_relative "../../../../lib/datadog/ci/git/cli"

RSpec.describe Datadog::CI::Git::Telemetry do
  describe ".git_command" do
    subject(:git_command) { described_class.git_command(command) }

    let(:command) { "git ls-remote --get-url" }

    before do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc)
        .with(Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMAND, 1, expected_tags)
    end

    let(:expected_tags) do
      {
        Datadog::CI::Ext::Telemetry::TAG_COMMAND => command
      }
    end

    it { git_command }
  end

  describe ".git_command_errors" do
    subject(:git_command_errors) { described_class.git_command_errors(command, exit_code: exit_code, executable_missing: executable_missing) }

    let(:command) { "git ls-remote --get-url" }
    before do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc)
        .with(Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMAND_ERRORS, 1, expected_tags)
    end

    context "when exit code is 1" do
      let(:exit_code) { 1 }
      let(:executable_missing) { false }

      let(:expected_tags) do
        {
          Datadog::CI::Ext::Telemetry::TAG_COMMAND => command,
          Datadog::CI::Ext::Telemetry::TAG_EXIT_CODE => exit_code.to_s
        }
      end

      it { git_command_errors }
    end

    context "when executable is missing" do
      let(:executable_missing) { true }
      let(:exit_code) { nil }

      let(:expected_tags) do
        {
          Datadog::CI::Ext::Telemetry::TAG_COMMAND => command,
          Datadog::CI::Ext::Telemetry::TAG_EXIT_CODE => Datadog::CI::Ext::Telemetry::ExitCode::MISSING
        }
      end

      it { git_command_errors }
    end
  end

  describe ".git_command_ms" do
    subject(:git_command_ms) { described_class.git_command_ms(command, duration_ms) }

    let(:command) { "git ls-remote --get-url" }
    let(:duration_ms) { 100 }

    before do
      expect(Datadog::CI::Utils::Telemetry).to receive(:distribution)
        .with(Datadog::CI::Ext::Telemetry::METRIC_GIT_COMMAND_MS, duration_ms, expected_tags)
    end

    let(:expected_tags) do
      {
        Datadog::CI::Ext::Telemetry::TAG_COMMAND => command
      }
    end

    it { git_command_ms }
  end

  describe ".track_error" do
    subject(:track_error) { described_class.track_error(error, command) }

    let(:command) { "git ls-remote --get-url" }

    context "when error is Errno::ENOENT" do
      let(:error) { Errno::ENOENT.new("No such file or directory") }

      it "calls git_command_errors with executable_missing: true" do
        expect(described_class).to receive(:git_command_errors).with(command, executable_missing: true)
        track_error
      end
    end

    context "when error is GitCommandExecutionError" do
      let(:status) { double(to_i: 1) }
      let(:error) { Datadog::CI::Git::CLI::GitCommandExecutionError.new("Git command failed", output: "error", command: "git", status: status) }

      it "calls git_command_errors with exit_code from status" do
        expect(described_class).to receive(:git_command_errors).with(command, exit_code: 1)
        track_error
      end
    end

    context "when error is a generic StandardError" do
      let(:error) { StandardError.new("Some other error") }

      it "calls git_command_errors with exit_code: -9000" do
        expect(described_class).to receive(:git_command_errors).with(command, exit_code: -9000)
        track_error
      end
    end
  end
end
