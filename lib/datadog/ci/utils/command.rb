# frozen_string_literal: true

require "open3"
require "datadog/core/utils/time"

module Datadog
  module CI
    module Utils
      # Providdes a way to call external commands with timeout
      module Command
        DEFAULT_TIMEOUT = 10 # seconds
        BUFFER_SIZE = 1024

        def self.exec_command(command, stdin_data: nil, timeout: DEFAULT_TIMEOUT)
          output = +""
          exit_value = nil
          timeout_reached = false

          begin
            stdin, stderrout, thread = Open3.popen2e(command)
            pid = thread[:pid]
            start = Core::Utils::Time.get_time

            # write input to stdin
            begin
              if stdin_data
                stdin.write(stdin_data)
              end
            rescue Errno::EPIPE
              return ["Error writing to stdin", nil]
            end

            stdin.close

            # wait for output and read from stdout/stderr
            while (Core::Utils::Time.get_time - start) < timeout
              # wait for data to appear in stderrout channel
              # maximum wait time 100ms
              Kernel.select([stderrout], [], [], 0.1)

              begin
                output << stderrout.read_nonblock(1024)
              rescue IO::WaitReadable
              rescue EOFError
                # we're done
                break
              end

              break unless thread.alive?
            end

            if thread.alive?
              begin
                Process.kill("TERM", pid)
                timeout_reached = true
              rescue
                # Process already terminated
              end
            end

            thread.join(1)
            exit_value = thread.value
          ensure
            stderrout.close if stderrout
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
      end
    end
  end
end
