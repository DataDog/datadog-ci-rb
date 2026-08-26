# frozen_string_literal: true

require "fileutils"
require "open3"
require "socket"
require "timeout"
require "tmpdir"

RSpec.describe "parallel_tests state isolation" do
  def start_parallel_run(environment, suite_path)
    stdin, stdout, stderr, wait_thread = Open3.popen3(
      environment,
      Gem.ruby,
      Gem.bin_path("parallel_tests", "parallel_rspec"),
      "--nice",
      "-n",
      "2",
      "--test-options",
      "--options /dev/null --format progress",
      suite_path,
      pgroup: true
    )
    stdin.close

    {
      stdout_thread: Thread.new { stdout.read },
      stderr_thread: Thread.new { stderr.read },
      wait_thread: wait_thread
    }
  end

  def finish_parallel_run(run)
    status = Timeout.timeout(60) { run.fetch(:wait_thread).value }
    [status, run.fetch(:stdout_thread).value, run.fetch(:stderr_thread).value]
  end

  def terminate_parallel_run(run)
    return unless run

    wait_thread = run.fetch(:wait_thread)
    return unless wait_thread.alive?

    Process.kill("TERM", -wait_thread.pid)
    wait_thread.join(5)
    Process.kill("KILL", -wait_thread.pid) if wait_thread.alive?
  rescue Errno::ESRCH
    nil
  ensure
    run&.fetch(:stdout_thread)&.join(5)
    run&.fetch(:stderr_thread)&.join(5)
  end

  def accept_barrier(server, expected_run)
    socket = Timeout.timeout(30) { server.accept }
    actual_run = Timeout.timeout(30) { socket.gets&.chomp }
    expect(actual_run).to eq(expected_run)
    socket
  end

  def write_suite(root, run:, failing: false)
    suite = File.join(root, run.downcase)
    FileUtils.mkdir_p(suite)

    target_path = File.join(suite, "target_spec.rb")
    target_body = if failing
      <<~RUBY
        RSpec.describe "CollisionRun#{run}" do
          it "always fails" do
            File.open(ENV.fetch("DD_COLLISION_TEST_COUNTER"), "a") { |file| file.puts("executed") }
            expect(:actual).to eq(:expected)
          end
        end
      RUBY
    else
      <<~RUBY
        RSpec.describe "CollisionRun#{run}" do
          it("passes") { expect(:actual).to eq(:actual) }
        end
      RUBY
    end

    File.write(target_path, target_body)
    File.write(
      File.join(suite, "other_spec.rb"),
      <<~RUBY
        RSpec.describe "CollisionRun#{run}Other" do
          it("passes") { expect(1 + 1).to eq(2) }
        end
      RUBY
    )

    [suite, target_path]
  end

  def run_environment(root, shared_tmpdir, barrier_path, run, target_path)
    support_file = File.expand_path("support/collision_test_transport.rb", __dir__)
    rubyopt = [ENV["RUBYOPT"], "-I#{File.expand_path("../../../../..", __dir__)}", "-r#{support_file}", "-rdatadog/ci/auto_instrument"]
      .compact
      .join(" ")

    {
      "TMPDIR" => shared_tmpdir,
      "RUBYOPT" => rubyopt,
      "DD_COLLISION_TEST_RUN" => run,
      "DD_COLLISION_TEST_BARRIER" => barrier_path,
      "DD_COLLISION_TEST_COUNTER" => File.join(root, "run-#{run.downcase}-executions"),
      "DD_COLLISION_TEST_TARGET_SUITE" => "CollisionRun#{run} at #{target_path}",
      "DD_SERVICE" => "collision-run-#{run.downcase}",
      "DD_ENV" => "collision-run-#{run.downcase}",
      "DD_GIT_REPOSITORY_URL" => "https://example.test/collision-run-#{run.downcase}.git",
      "DD_GIT_COMMIT_SHA" => (run == "A") ? "a" * 40 : "b" * 40,
      "DD_CIVISIBILITY_AGENTLESS_ENABLED" => "1",
      "DD_API_KEY" => "unused-fake-key",
      "DD_CIVISIBILITY_ITR_ENABLED" => "0",
      "DD_CIVISIBILITY_GIT_METADATA_UPLOAD_ENABLED" => "0",
      "DD_CIVISIBILITY_FLAKY_RETRY_ENABLED" => "1",
      "DD_CIVISIBILITY_FLAKY_RETRY_COUNT" => "5",
      "DD_CIVISIBILITY_EARLY_FLAKE_DETECTION_ENABLED" => "0",
      "DD_TEST_MANAGEMENT_ENABLED" => "1",
      "DD_TEST_MANAGEMENT_ATTEMPT_TO_FIX_RETRIES" => "0",
      "DD_INSTRUMENTATION_TELEMETRY_ENABLED" => "0"
    }
  end

  it "does not mix settings and test management state between concurrent invocations sharing TMPDIR" do
    Dir.mktmpdir("dd-ci-parallel-tests-collision", "/tmp") do |root|
      shared_tmpdir = File.join(root, "tmp")
      FileUtils.mkdir_p(shared_tmpdir)
      suite_a, target_a = write_suite(root, run: "A", failing: true)
      suite_b, target_b = write_suite(root, run: "B")

      barrier_path = File.join(root, "barrier.sock")
      server = UNIXServer.new(barrier_path)
      run_a = start_parallel_run(run_environment(root, shared_tmpdir, barrier_path, "A", target_a), suite_a)
      barrier_a = accept_barrier(server, "A")

      run_b = start_parallel_run(run_environment(root, shared_tmpdir, barrier_path, "B", target_b), suite_b)
      barrier_b = accept_barrier(server, "B")

      barrier_a.puts("continue")
      status_a, stdout_a, stderr_a = finish_parallel_run(run_a)
      barrier_b.puts("continue")
      status_b, stdout_b, stderr_b = finish_parallel_run(run_b)

      aggregate_failures do
        expect(status_a).to be_success, "Run A failed:\n#{stdout_a}\n#{stderr_a}"
        expect(File.readlines(File.join(root, "run-a-executions")).size).to eq(1)
        expect(status_b).to be_success, "Run B failed:\n#{stdout_b}\n#{stderr_b}"
      end
    ensure
      barrier_a&.close
      barrier_b&.close
      server&.close
      terminate_parallel_run(run_a)
      terminate_parallel_run(run_b)
    end
  end
end
