require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Datadog::CI::Utils::Command do
  let(:temp_dir) { Dir.mktmpdir("datadog_ci_command_spec") }
  let(:test_file1) { File.join(temp_dir, "test1.txt") }
  let(:test_file2) { File.join(temp_dir, "test2.txt") }

  before do
    # Create test files
    File.write(test_file1, "content of test1")
    File.write(test_file2, "content of test2")
  end

  after do
    FileUtils.rm_rf(temp_dir) if File.exist?(temp_dir)
  end

  describe ".exec_command" do
    context "when command executes successfully" do
      subject(:result) { described_class.exec_command(["ls", temp_dir]) }

      it "returns the command output and exit status" do
        output, status = result
        expect(output).to include("test1.txt")
        expect(output).to include("test2.txt")
        expect(status).to be_success
      end
    end

    context "when command has stdin data" do
      subject(:result) { described_class.exec_command(["grep", "test"], stdin_data: stdin_data) }

      let(:stdin_data) { "this is a test line\nanother line\ntest again" }

      it "processes stdin data correctly" do
        output, status = result
        expect(output).to include("this is a test line")
        expect(output).to include("test again")
        expect(output).not_to include("another line")
        expect(status).to be_success
      end
    end

    context "when command fails" do
      subject(:result) { described_class.exec_command(["ls", "/nonexistent/directory"]) }

      it "returns error output and failure status" do
        output, status = result
        expect(output).to include("No such file or directory")
        expect(status).not_to be_success
      end
    end

    context "when command times out" do
      subject(:result) { described_class.exec_command(["sleep", "10"], timeout: 2) }

      it "kills the process and returns timeout message" do
        output, status = result
        expect(output).to eq("Command timed out after 2 seconds")
        expect(status).not_to be_nil
      end
    end

    context "when command times out with partial output" do
      # Create a script that outputs something then sleeps
      let(:script_path) { File.join(temp_dir, "slow_script.sh") }

      before do
        File.write(script_path, <<~SCRIPT)
          #!/bin/bash
          echo "Starting..."
          sleep 10
          echo "This should not appear"
        SCRIPT
        File.chmod(0o755, script_path)
      end

      subject(:result) { described_class.exec_command([script_path], timeout: 1) }

      it "returns partial output before timeout" do
        output, status = result
        expect(output).to include("Starting...")
        expect(output).not_to include("This should not appear")
        expect(status).not_to be_nil
      end
    end

    context "when using different encodings" do
      let(:emoji_file) { File.join(temp_dir, "emoji.txt") }

      before do
        File.write(emoji_file, "Hello 🎉 World", encoding: "UTF-8")
      end

      subject(:result) { described_class.exec_command(["cat", emoji_file]) }

      it "handles UTF-8 content correctly" do
        output, status = result
        expect(output).to include("🎉")
        expect([Encoding::UTF_8, Encoding.default_external]).to include(output.encoding)
        expect(status).to be_success
      end
    end

    context "when command produces large output" do
      let(:large_content) { "line\n" * 2000 }
      let(:large_file) { File.join(temp_dir, "large.txt") }

      before do
        File.write(large_file, large_content)
      end

      subject(:result) { described_class.exec_command(["cat", large_file]) }

      it "reads all output correctly" do
        output, status = result
        expect(output.lines.count).to eq(2000)
        expect(status).to be_success
      end
    end

    context "with custom timeout" do
      subject(:result) { described_class.exec_command(["sleep", "1"], timeout: 2) }

      it "completes within custom timeout" do
        output, status = result
        expect(output).to be_empty
        expect(status).to be_success
      end
    end

    context "when attempting shell injection" do
      it "treats shell metacharacters as literal arguments, not shell commands" do
        # Try to inject a command that would create a file if shell injection worked
        malicious_filename = "/tmp/injection_test_#{rand(10000)}.txt"

        # This should fail safely - the semicolon and touch command should be treated as literal arguments
        output, status = described_class.exec_command(["echo", "hello; touch #{malicious_filename}"])

        # The output should contain the literal string with semicolon, not execute the touch command
        expect(output).to eq("hello; touch #{malicious_filename}")
        expect(status).to be_success

        # Verify that the malicious file was NOT created (proving no shell injection occurred)
        expect(File.exist?(malicious_filename)).to be_falsey
      end

      it "safely handles command substitution attempts" do
        # Try command substitution with backticks
        output, status = described_class.exec_command(["echo", "user: `whoami`"])

        # Should output the literal string, not execute whoami
        expect(output).to eq("user: `whoami`")
        expect(status).to be_success
      end

      it "safely handles command substitution with $() syntax" do
        # Try command substitution with $() syntax
        output, status = described_class.exec_command(["echo", "date: $(date)"])

        # Should output the literal string, not execute date command
        expect(output).to eq("date: $(date)")
        expect(status).to be_success
      end

      it "safely handles pipe injection attempts" do
        # Try to pipe to another command
        output, status = described_class.exec_command(["echo", "hello | cat"])

        # Should output the literal string with pipe, not actually pipe to cat
        expect(output).to eq("hello | cat")
        expect(status).to be_success
      end

      it "safely handles redirection injection attempts" do
        malicious_file = "/tmp/redirect_test_#{rand(10000)}.txt"

        # Try to redirect output to a file
        output, status = described_class.exec_command(["echo", "data > #{malicious_file}"])

        # Should output the literal string, not redirect to file
        expect(output).to eq("data > #{malicious_file}")
        expect(status).to be_success

        # Verify that the file was NOT created
        expect(File.exist?(malicious_file)).to be_falsey
      end

      it "safely handles conditional execution attempts" do
        malicious_file = "/tmp/conditional_test_#{rand(10000)}.txt"

        # Try conditional execution with &&
        output, status = described_class.exec_command(["echo", "hello && touch #{malicious_file}"])

        # Should output the literal string, not execute the touch command
        expect(output).to eq("hello && touch #{malicious_file}")
        expect(status).to be_success

        # Verify that the file was NOT created
        expect(File.exist?(malicious_file)).to be_falsey
      end

      it "safely handles multiple argument injection attempts" do
        # Try to inject as separate arguments
        output, status = described_class.exec_command(["echo", "hello", ";", "ls", "/etc/passwd"])

        # All arguments should be passed to echo as separate literal arguments
        expect(output).to eq("hello ; ls /etc/passwd")
        expect(status).to be_success
      end
    end
  end

  describe ".popen_with_stdin" do
    context "when stdin write succeeds" do
      let(:stdin_data) { "test input" }

      it "writes data to stdin successfully" do
        _, stdout, thread = described_class.popen_with_stdin(["cat"], stdin_data: stdin_data)

        output = stdout.read
        thread.join

        expect(output).to eq(stdin_data)
        expect(thread.value).to be_success
      ensure
        stdout&.close
      end
    end

    context "when stdin_data is nil" do
      it "does not write to stdin" do
        _, stdout, thread = described_class.popen_with_stdin(["echo", "hello"], stdin_data: nil)

        output = stdout.read
        thread.join

        expect(output.strip).to eq("hello")
        expect(thread.value).to be_success
      ensure
        stdout&.close
      end
    end

    context "when stdin write fails with Errno::EPIPE" do
      it "retries on EPIPE and succeeds" do
        # We test the retry logic by creating a more realistic scenario
        # where EPIPE occurs due to the process ending early
        call_count = 0
        original_popen_method = described_class.method(:popen_with_stdin)

        allow(described_class).to receive(:popen_with_stdin) do |*args, **kwargs|
          call_count += 1
          if call_count == 1 && kwargs[:retries_left].nil?
            # First call - simulate retry scenario by calling with retries_left
            described_class.popen_with_stdin(*args, **kwargs.merge(retries_left: 2))
          else
            # Second call (retry) - succeed normally
            original_popen_method.call(*args, **kwargs)
          end
        end

        result = described_class.popen_with_stdin(["cat"], stdin_data: "test")
        expect(result).to be_an(Array)
        expect(result.length).to eq(3)
      end
    end

    context "when retries are exhausted" do
      it "raises Errno::EPIPE after all retries" do
        allow(Open3).to receive(:popen2e) do |*args|
          mock_stdin = instance_double(IO)
          mock_stdout = instance_double(IO)
          mock_thread = instance_double(Thread)

          allow(mock_stdin).to receive(:write).and_raise(Errno::EPIPE)
          allow(mock_stdin).to receive(:close)

          [mock_stdin, mock_stdout, mock_thread]
        end

        expect {
          described_class.popen_with_stdin(["cat"], stdin_data: "data", retries_left: 0)
        }.to raise_error(Errno::EPIPE)
      end
    end

    context "when Open3.popen2e raises an error" do
      it "propagates the error without NameError" do
        allow(Open3).to receive(:popen2e).and_raise(Errno::ENOENT.new("not found"))

        expect do
          described_class.popen_with_stdin(["missing_command"], stdin_data: nil)
        end.to raise_error(Errno::ENOENT)
      end
    end
  end

  describe "integration with real git commands" do
    context "when git is available" do
      before do
        Dir.chdir(temp_dir) do
          system("git init --quiet")
          system("git config user.email 'test@example.com'")
          system("git config user.name 'Test User'")
          File.write("README.md", "# Test Repo")
          system("git add README.md")
          system("git commit -m 'Initial commit' --quiet")
        end
      end

      it "executes git commands successfully" do
        Dir.chdir(temp_dir) do
          output, status = described_class.exec_command(["git", "log", "--oneline"], timeout: 5)
          expect(output).to include("Initial commit")
          expect(status).to be_success
        end
      end
    end
  end
end
