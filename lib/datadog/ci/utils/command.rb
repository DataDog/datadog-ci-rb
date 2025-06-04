# frozen_string_literal: true

require "open3"
require "datadog/core/utils/time"

module Datadog
  module CI
    module Utils
      # Provides a way to call external commands with timeout
      module Command
        DEFAULT_TIMEOUT = 10 # seconds
        BUFFER_SIZE = 1024

        OPEN_STDIN_RETRY_COUNT = 3

        # Executes a command with optional timeout and stdin data
        #
        # @param command [Array<String>] Command to execute.
        # @param stdin_data [String, nil] Data to write to stdin
        # @param timeout [Integer] Maximum execution time in seconds
        # @return [Array<String, Process::Status?>] Output and exit status
        #
        # @example Safe usage with array (recommended)
        #   Command.exec_command(["git", "log", "-n", "1"])
        #
        #
        def self.exec_command(command, stdin_data: nil, timeout: DEFAULT_TIMEOUT)
          output = +""
          exit_value = nil
          timeout_reached = false

          begin
            start = Core::Utils::Time.get_time

            _, stderrout, thread = popen_with_stdin(command, stdin_data: stdin_data)
            pid = thread[:pid]

            # wait for output and read from stdout/stderr
            while (Core::Utils::Time.get_time - start) < timeout
              # wait for data to appear in stderrout channel
              # maximum wait time 100ms
              Kernel.select([stderrout], [], [], 0.1)

              begin
                output << stderrout.read_nonblock(1024)
              rescue IO::WaitReadable
              rescue EOFError
                # we're done here, we return from this cycle when we processed the whole output of the command
                break
              end
            end

            if (Core::Utils::Time.get_time - start) > timeout
              timeout_reached = true
            end

            if thread.alive?
              begin
                Process.kill("TERM", pid)
              rescue
                # Process already terminated
              end
            end

            thread.join(1)
            exit_value = thread.value
          rescue Errno::EPIPE
            return ["Error writing to stdin", nil]
          ensure
            stderrout&.close
          end

          # we read command's output as binary so now we need to set an appropriate encoding for the result
          encoding = Encoding.default_external

          # Sometimes Encoding.default_external is somehow set to US-ASCII which breaks
          # commit messages with UTF-8 characters like emojis
          # We force output's encoding to be UTF-8 in this case
          # This is safe to do as UTF-8 is compatible with US-ASCII
          if Encoding.default_external == Encoding::US_ASCII
            encoding = Encoding::UTF_8
          end

          output.force_encoding(encoding)
          output.strip! # There's always a "\n" at the end of the command output

          if timeout_reached && output.empty?
            output = "Command timed out after #{timeout} seconds"
          end

          [output, exit_value]
        end

        def self.popen_with_stdin(command, stdin_data: nil, retries_left: OPEN_STDIN_RETRY_COUNT)
          result = Open3.popen2e(*command)
          stdin = result.first

          # write input to stdin
          begin
            stdin.write(stdin_data) if stdin_data
          rescue Errno::EPIPE => e
            if retries_left > 0
              return popen_with_stdin(command, stdin_data: stdin_data, retries_left: retries_left - 1)
            else
              raise e
            end
          end

          result
        ensure
          stdin.close
        end
      end
    end
  end
end
