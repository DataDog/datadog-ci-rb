# frozen_string_literal: true

require "spec_helper"

require "datadog/ci/git/cli"

RSpec.describe Datadog::CI::Git::CLI do
  # Clear the safe_directory cache before each test
  before do
    described_class.remove_instance_variable(:@safe_directory) if described_class.instance_variable_defined?(:@safe_directory)
  end

  describe ".exec_git_command" do
    let(:command) { ["rev-parse", "HEAD"] }
    let(:stdin_data) { nil }
    let(:timeout) { described_class::SHORT_TIMEOUT }
    # Use the actual computed safe directory for tests
    let(:safe_dir) { described_class.safe_directory }

    # Helper to build the expected git command with safe.directory
    def git_command_with_safe_dir(cmd, safe_directory: described_class.safe_directory)
      ["git", "-c", "safe.directory=#{safe_directory}"] + cmd
    end

    context "when command succeeds" do
      let(:output) { "abc123\n" }
      let(:status) { double("status", success?: true) }

      before do
        allow(Datadog::CI::Utils::Command).to receive(:exec_command)
          .with(git_command_with_safe_dir(command), stdin_data: stdin_data, timeout: timeout)
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
          .with(git_command_with_safe_dir(command), stdin_data: stdin_data, timeout: timeout)
          .and_return([output, status])
      end

      it "raises GitCommandExecutionError" do
        expect do
          described_class.exec_git_command(command, stdin: stdin_data, timeout: timeout)
        end.to raise_error(described_class::GitCommandExecutionError) do |error|
          expect(error.output).to eq(output)
          expect(error.command).to eq("rev-parse HEAD")
          expect(error.status).to eq(status)
          expect(error.message).to include("Failed to run git command [rev-parse HEAD]")
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
          .with(git_command_with_safe_dir(command), stdin_data: stdin_data, timeout: timeout)
          .and_return([output, status])
      end

      it "raises GitCommandExecutionError" do
        expect do
          described_class.exec_git_command(command, stdin: stdin_data, timeout: timeout)
        end.to raise_error(described_class::GitCommandExecutionError) do |error|
          expect(error.output).to eq(output)
          expect(error.command).to eq("rev-parse HEAD")
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
          .with(git_command_with_safe_dir(command), stdin_data: stdin_data, timeout: timeout)
          .and_return([output, status])
      end

      it "passes stdin data to the command" do
        result = described_class.exec_git_command(command, stdin: stdin_data, timeout: timeout)
        expect(result).to eq(output)
        expect(Datadog::CI::Utils::Command).to have_received(:exec_command)
          .with(git_command_with_safe_dir(command), stdin_data: stdin_data, timeout: timeout)
      end
    end

    context "with custom timeout" do
      let(:custom_timeout) { 60 }
      let(:output) { "output" }
      let(:status) { double("status", success?: true) }

      before do
        allow(Datadog::CI::Utils::Command).to receive(:exec_command)
          .with(git_command_with_safe_dir(command), stdin_data: stdin_data, timeout: custom_timeout)
          .and_return([output, status])
      end

      it "uses the custom timeout" do
        result = described_class.exec_git_command(command, timeout: custom_timeout)
        expect(result).to eq(output)
        expect(Datadog::CI::Utils::Command).to have_received(:exec_command)
          .with(git_command_with_safe_dir(command), stdin_data: nil, timeout: custom_timeout)
      end
    end

    context "with default timeout" do
      let(:output) { "output" }
      let(:status) { double("status", success?: true) }

      before do
        allow(Datadog::CI::Utils::Command).to receive(:exec_command)
          .with(git_command_with_safe_dir(command), stdin_data: nil, timeout: described_class::SHORT_TIMEOUT)
          .and_return([output, status])
      end

      it "uses the default SHORT_TIMEOUT" do
        result = described_class.exec_git_command(command)
        expect(result).to eq(output)
        expect(Datadog::CI::Utils::Command).to have_received(:exec_command)
          .with(git_command_with_safe_dir(command), stdin_data: nil, timeout: described_class::SHORT_TIMEOUT)
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

  describe ".safe_directory" do
    # Clear cache before each test
    before do
      described_class.remove_instance_variable(:@safe_directory) if described_class.instance_variable_defined?(:@safe_directory)
    end

    it "caches the result" do
      first_result = described_class.safe_directory
      second_result = described_class.safe_directory

      expect(first_result).to eq(second_result)
      expect(described_class.instance_variable_get(:@safe_directory)).to eq(first_result)
    end

    it "finds the repository root by traversing up from current directory" do
      result = described_class.safe_directory
      expect(File.exist?(File.join(result, ".git"))).to be true
    end
  end

  describe ".find_git_directory" do
    context "when .git directory exists in parent directory" do
      it "returns the directory containing .git" do
        # Start from a subdirectory within the repo
        start_dir = File.join(Dir.pwd, "lib")
        result = described_class.find_git_directory(start_dir)
        expect(File.exist?(File.join(result, ".git"))).to be true
      end
    end

    context "when .git directory exists in current directory" do
      it "returns the current directory" do
        # We're in the repo root
        result = described_class.find_git_directory(Dir.pwd)
        expect(result).to eq(File.expand_path(Dir.pwd))
      end
    end

    context "when .git is a file (worktrees/submodules)" do
      let(:tmpdir) { Dir.mktmpdir }
      let(:worktree_path) { File.join(tmpdir, "worktree") }
      let(:subdir_path) { File.join(worktree_path, "subdir", "nested") }

      before do
        # Create a fake worktree structure where .git is a file
        FileUtils.mkdir_p(subdir_path)
        # In worktrees/submodules, .git is a file containing "gitdir: /path/to/git"
        File.write(File.join(worktree_path, ".git"), "gitdir: /some/path/.git/worktrees/test")
      end

      after do
        FileUtils.remove_entry(tmpdir)
      end

      it "returns the directory containing the .git file" do
        result = described_class.find_git_directory(subdir_path)
        expect(result).to eq(worktree_path)
      end

      it "detects .git as a file, not just a directory" do
        git_path = File.join(worktree_path, ".git")
        expect(File.exist?(git_path)).to be true
        expect(File.file?(git_path)).to be true
        expect(File.directory?(git_path)).to be false
      end
    end

    context "when no .git is found" do
      it "returns the original directory" do
        # Use /tmp which shouldn't have a .git
        result = described_class.find_git_directory("/tmp")
        expect(result).to eq("/tmp")
      end
    end
  end
end
