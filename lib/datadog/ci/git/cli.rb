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
        # @param cmd [Array<String>] The git command as an array of strings
        # @param stdin [String, nil] Optional stdin data to pass to the command
        # @param timeout [Integer] Timeout in seconds for the command execution
        # @return [String, nil] The command output, or nil if the output is empty
        # @raise [GitCommandExecutionError] If the command fails or times out
        def self.exec_git_command(cmd, stdin: nil, timeout: SHORT_TIMEOUT)
          # @type var out: String
          # @type var status: Process::Status?
          out, status = Utils::Command.exec_command(cmd, stdin_data: stdin, timeout: timeout)

          if status.nil? || !status.success?
            # Convert command to string representation for error message
            cmd_str = cmd.is_a?(Array) ? cmd.join(" ") : cmd
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
      end
    end
  end
end
