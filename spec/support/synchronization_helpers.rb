# frozen_string_literal: true

require "tempfile"

module SynchronizationHelpers
  def expect_in_fork(fork_expectations: nil, timeout_seconds: 10)
    fork_expectations ||= proc { |status:, stdout:, stderr:|
      expect(status && status.success?).to be(true), "STDOUT:`#{stdout}` STDERR:`#{stderr}"
    }

    fork_stdout = Tempfile.new("ddtrace-rspec-expect-in-fork-stdout")
    fork_stderr = Tempfile.new("ddtrace-rspec-expect-in-fork-stderr")
    begin
      # Start in fork
      pid = fork do
        # Capture forked output
        $stdout.reopen(fork_stdout)
        $stderr.reopen(fork_stderr) # STDERR captures RSpec failures. We print it in case the fork fails on exit.

        yield
      end

      fork_stderr.close
      fork_stdout.close

      # Wait for fork to finish, retrieve its status.
      # Enforce timeout to ensure test fork doesn't hang the test suite.
      _, status = try_wait_until(seconds: timeout_seconds) { Process.wait2(pid, Process::WNOHANG) }

      stdout = File.read(fork_stdout.path)
      stderr = File.read(fork_stderr.path)

      # Capture forked execution information
      result = {status: status, stdout: stdout, stderr: stderr}

      # Expect fork and assertions to have completed successfully.
      fork_expectations.call(**result)

      result
    rescue => e
      stdout ||= File.read(fork_stdout.path)
      stderr ||= File.read(fork_stderr.path)

      puts stdout
      warn stderr

      raise e
    ensure
      begin
        Process.kill("KILL", pid)
      rescue
        nil
      end # Prevent zombie processes on failure

      fork_stdout.unlink
      fork_stderr.unlink
    end
  end

  # Waits for the condition provided by the block argument to return truthy.
  #
  # Waits for 5 seconds by default.
  #
  # Can be configured by setting either:
  #   * `seconds`, or
  #   * `attempts` and `backoff`
  #
  # @yieldreturn [Boolean] block executed until it returns truthy
  # @param [Numeric] seconds number of seconds to wait
  # @param [Integer] attempts number of attempts at checking the condition
  # @param [Numeric] backoff wait time between condition checking attempts
  def try_wait_until(seconds: nil, attempts: nil, backoff: nil)
    raise "Provider either `seconds` or `attempts` & `backoff`, not both" if seconds && (attempts || backoff)

    if seconds
      attempts = seconds * 10
      backoff = 0.1
    else
      # 5 seconds by default, but respect the provide values if any.
      attempts ||= 50
      backoff ||= 0.1
    end

    # It's common for tests to want to run simple tasks in a background thread
    # but call this method without the thread having even time to start.
    #
    # We add an extra attempt, interleaved by `Thread.pass`, in order to allow for
    # those simple cases to quickly succeed without a timed `sleep` call. This will
    # save simple test one `backoff` seconds sleep cycle.
    #
    # The total configured timeout is not reduced.
    (attempts + 1).times do |i|
      result = yield(attempts)
      return result if result

      if i == 0
        Thread.pass
      else
        sleep(backoff)
      end
    end

    raise("Wait time exhausted!")
  end
end
