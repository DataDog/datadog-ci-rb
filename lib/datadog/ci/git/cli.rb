# frozen_string_literal: true

require_relative "../utils/command"

module Datadog
  module CI
    module Git
      module CLI
        class GitCommandExecutionError < StandardError
          attr_reader :output, :command, :status
          def initialize(message, output:, command:, status:)
            super(message)

            @output = output
            @command = command
            @status = status
          end
        end

        # Timeout constants for git commands (in seconds)
        # These values were set based on internal telemetry
        UNSHALLOW_TIMEOUT = 500
        LONG_TIMEOUT = 30
        SHORT_TIMEOUT = 3

        # Execute a git command with optional stdin input and timeout
        #
        # All git commands are executed with the `-c safe.directory` option
        # to handle cases where the repository is owned by a different user
        # (common in CI environments with containerized builds).
        #
        # @param cmd [Array<String>] The git command as an array of strings
        # @param stdin [String, nil] Optional stdin data to pass to the command
        # @param timeout [Integer] Timeout in seconds for the command execution
        # @return [String, nil] The command output, or nil if the output is empty
        # @raise [GitCommandExecutionError] If the command fails or times out
        def self.exec_git_command(cmd, stdin: nil, timeout: SHORT_TIMEOUT)
          # @type var out: String
          # @type var status: Process::Status?
          out, status = Utils::Command.exec_command(
            ["git", "-c", "safe.directory=#{safe_directory}"] + cmd,
            stdin_data: stdin,
            timeout: timeout
          )

          if status.nil? || !status.success?
            # Convert command to string representation for error message
            cmd_str = cmd.join(" ")
            raise GitCommandExecutionError.new(
              "Failed to run git command [#{cmd_str}] with input [#{stdin}] and output [#{out}]. Status: #{status}",
              output: out,
              command: cmd_str,
              status: status
            )
          end

          return nil if out.empty?

          out
        end

        # Returns the directory to use for git's safe.directory config.
        # This is cached to avoid repeated filesystem lookups.
        #
        # Traverses up from current directory to find the nearest .git folder
        # and returns its parent (the repository root). Falls back to current
        # working directory if no .git folder is found.
        #
        # @return [String] The safe directory path
        def self.safe_directory
          return @safe_directory if defined?(@safe_directory)

          @safe_directory = find_git_directory(Dir.pwd)
        end

        # Traverses up from the given directory to find the nearest .git folder.
        # Returns the repository root (parent of .git) if found, otherwise the original directory.
        #
        # @param start_dir [String] The directory to start searching from
        # @return [String] The repository root path or the start directory if not found
        def self.find_git_directory(start_dir)
          current_dir = File.expand_path(start_dir)

          loop do
            git_path = File.join(current_dir, ".git")

            if File.directory?(git_path)
              return current_dir
            end

            parent_dir = File.dirname(current_dir)

            # Reached the root directory
            break if parent_dir == current_dir

            current_dir = parent_dir
          end

          # Fallback to original directory if no .git found
          start_dir
        end
      end
    end
  end
end
