# frozen_string_literal: true

require "spec_helper"

require "datadog/ci/git/cli"

RSpec.describe Datadog::CI::Git::CLI do
  describe ".exec_git_command" do
    let(:command) { ["git", "rev-parse", "HEAD"] }
    let(:stdin_data) { nil }
    let(:timeout) { described_class::SHORT_TIMEOUT }

    context "when command succeeds" do
      let(:output) { "abc123\n" }
      let(:status) { double("status", success?: true) }

      before do
        allow(Datadog::CI::Utils::Command).to receive(:exec_command)
          .with(command, stdin_data: stdin_data, timeout: timeout)
          .and_return([output, status])
      end

      it "returns the command output" do
        result = described_class.exec_git_command(command, stdin: stdin_data, timeout: timeout)
        expect(result).to eq(output)
      end

      context "when output is empty" do
        let(:output) { "" }

        it "returns nil" do
          result = described_class.exec_git_command(command, stdin: stdin_data, timeout: timeout)
          expect(result).to be_nil
        end
      end
    end

    context "when command fails" do
      let(:output) { "fatal: not a git repository" }
      let(:status) { double("status", success?: false) }

      before do
        allow(Datadog::CI::Utils::Command).to receive(:exec_command)
          .with(command, stdin_data: stdin_data, timeout: timeout)
          .and_return([output, status])
      end

      it "raises GitCommandExecutionError" do
        expect do
          described_class.exec_git_command(command, stdin: stdin_data, timeout: timeout)
        end.to raise_error(described_class::GitCommandExecutionError) do |error|
          expect(error.output).to eq(output)
          expect(error.command).to eq("git rev-parse HEAD")
          expect(error.status).to eq(status)
          expect(error.message).to include("Failed to run git command [git rev-parse HEAD]")
          expect(error.message).to include("with input []")
          expect(error.message).to include("and output [#{output}]")
        end
      end
    end

    context "when status is nil" do
      let(:output) { "some output" }
      let(:status) { nil }

      before do
        allow(Datadog::CI::Utils::Command).to receive(:exec_command)
          .with(command, stdin_data: stdin_data, timeout: timeout)
          .and_return([output, status])
      end

      it "raises GitCommandExecutionError" do
        expect do
          described_class.exec_git_command(command, stdin: stdin_data, timeout: timeout)
        end.to raise_error(described_class::GitCommandExecutionError) do |error|
          expect(error.output).to eq(output)
          expect(error.command).to eq("git rev-parse HEAD")
          expect(error.status).to be_nil
        end
      end
    end

    context "with stdin data" do
      let(:stdin_data) { "some input data" }
      let(:output) { "processed output" }
      let(:status) { double("status", success?: true) }

      before do
        allow(Datadog::CI::Utils::Command).to receive(:exec_command)
          .with(command, stdin_data: stdin_data, timeout: timeout)
          .and_return([output, status])
      end

      it "passes stdin data to the command" do
        result = described_class.exec_git_command(command, stdin: stdin_data, timeout: timeout)
        expect(result).to eq(output)
        expect(Datadog::CI::Utils::Command).to have_received(:exec_command)
          .with(command, stdin_data: stdin_data, timeout: timeout)
      end
    end

    context "with custom timeout" do
      let(:custom_timeout) { 60 }
      let(:output) { "output" }
      let(:status) { double("status", success?: true) }

      before do
        allow(Datadog::CI::Utils::Command).to receive(:exec_command)
          .with(command, stdin_data: stdin_data, timeout: custom_timeout)
          .and_return([output, status])
      end

      it "uses the custom timeout" do
        result = described_class.exec_git_command(command, timeout: custom_timeout)
        expect(result).to eq(output)
        expect(Datadog::CI::Utils::Command).to have_received(:exec_command)
          .with(command, stdin_data: nil, timeout: custom_timeout)
      end
    end

    context "with default timeout" do
      let(:output) { "output" }
      let(:status) { double("status", success?: true) }

      before do
        allow(Datadog::CI::Utils::Command).to receive(:exec_command)
          .with(command, stdin_data: nil, timeout: described_class::SHORT_TIMEOUT)
          .and_return([output, status])
      end

      it "uses the default SHORT_TIMEOUT" do
        result = described_class.exec_git_command(command)
        expect(result).to eq(output)
        expect(Datadog::CI::Utils::Command).to have_received(:exec_command)
          .with(command, stdin_data: nil, timeout: described_class::SHORT_TIMEOUT)
      end
    end
  end

  describe "::GitCommandExecutionError" do
    let(:message) { "Command failed" }
    let(:output) { "error output" }
    let(:command) { "git status" }
    let(:status) { double("status") }

    subject(:error) do
      described_class::GitCommandExecutionError.new(
        message,
        output: output,
        command: command,
        status: status
      )
    end

    it "has the correct message" do
      expect(error.message).to eq(message)
    end

    it "has the correct output" do
      expect(error.output).to eq(output)
    end

    it "has the correct command" do
      expect(error.command).to eq(command)
    end

    it "has the correct status" do
      expect(error.status).to eq(status)
    end

    it "is a StandardError" do
      expect(error).to be_a(StandardError)
    end
  end

  describe "timeout constants" do
    describe "::SHORT_TIMEOUT" do
      it "is defined as 3 seconds" do
        expect(described_class::SHORT_TIMEOUT).to eq(3)
      end
    end

    describe "::LONG_TIMEOUT" do
      it "is defined as 30 seconds" do
        expect(described_class::LONG_TIMEOUT).to eq(30)
      end
    end

    describe "::UNSHALLOW_TIMEOUT" do
      it "is defined as 500 seconds" do
        expect(described_class::UNSHALLOW_TIMEOUT).to eq(500)
      end
    end
  end
end
