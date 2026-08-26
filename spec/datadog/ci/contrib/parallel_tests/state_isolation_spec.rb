# frozen_string_literal: true

require "fileutils"
require "json"
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

  def write_worker_barrier(root)
    barrier = File.join(root, "worker_barrier.rb")
    File.write(
      barrier,
      <<~RUBY
        if ENV.key?("TEST_ENV_NUMBER")
          require "socket"

          UNIXSocket.open(ENV.fetch("DD_COLLISION_TEST_BARRIER")) do |socket|
            socket.puts(ENV.fetch("DD_COLLISION_TEST_RUN"))
            response = socket.gets&.chomp
            raise "Unexpected collision test barrier response: \#{response.inspect}" unless response == "continue"
          end
        end
      RUBY
    )
    barrier
  end

  def run_environment(root, shared_tmpdir, barrier_path, run, worker_barrier, backend_url)
    rubyopt = [ENV["RUBYOPT"], "-I#{File.expand_path("../../../../..", __dir__)}", "-r#{worker_barrier}", "-rdatadog/ci/auto_instrument"]
      .compact
      .join(" ")

    {
      "TMPDIR" => shared_tmpdir,
      "RUBYOPT" => rubyopt,
      "TEST_ENV_NUMBER" => nil,
      "DD_COLLISION_TEST_RUN" => run,
      "DD_COLLISION_TEST_BARRIER" => barrier_path,
      "DD_COLLISION_TEST_COUNTER" => File.join(root, "run-#{run.downcase}-executions"),
      "DD_SERVICE" => "collision-run-#{run.downcase}",
      "DD_ENV" => "collision-run-#{run.downcase}",
      "DD_GIT_REPOSITORY_URL" => "https://example.test/collision-run-#{run.downcase}.git",
      "DD_GIT_COMMIT_SHA" => (run == "A") ? "a" * 40 : "b" * 40,
      "DD_CIVISIBILITY_AGENTLESS_ENABLED" => "1",
      "DD_CIVISIBILITY_AGENTLESS_URL" => backend_url,
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

  def write_lifecycle_suite(root)
    suite = File.join(root, "lifecycle")
    FileUtils.mkdir_p(suite)

    %w[fast slow].each do |worker|
      File.write(
        File.join(suite, "#{worker}_spec.rb"),
        <<~RUBY
          require "socket"

          RSpec.describe "#{worker.capitalize}Worker" do
            it "waits at the lifecycle barrier" do
              UNIXSocket.open(ENV.fetch("DD_PARALLEL_TEST_LIFECYCLE_BARRIER")) do |socket|
                socket.puts(["#{worker}", Process.pid].join(","))
                raise "barrier closed" unless socket.gets&.chomp == "continue"
              end

              expect(1 + 1).to eq(2)
            end
          end
        RUBY
      )
    end

    suite
  end

  def lifecycle_environment(shared_tmpdir, barrier_path, backend_url)
    rubyopt = [
      ENV["RUBYOPT"],
      "-I#{File.expand_path("../../../../..", __dir__)}",
      "-rdatadog/ci/auto_instrument"
    ].compact.join(" ")

    {
      "TMPDIR" => shared_tmpdir,
      "RUBYOPT" => rubyopt,
      "DD_PARALLEL_TEST_LIFECYCLE_BARRIER" => barrier_path,
      "DD_SERVICE" => "parallel-tests-lifecycle",
      "DD_ENV" => "test",
      "DD_GIT_REPOSITORY_URL" => "https://example.test/parallel-tests-lifecycle.git",
      "DD_GIT_COMMIT_SHA" => "a" * 40,
      "DD_CIVISIBILITY_AGENTLESS_ENABLED" => "1",
      "DD_CIVISIBILITY_AGENTLESS_URL" => backend_url,
      "DD_API_KEY" => "unused-fake-key",
      "DD_CIVISIBILITY_ITR_ENABLED" => "0",
      "DD_CIVISIBILITY_GIT_METADATA_UPLOAD_ENABLED" => "0",
      "DD_CIVISIBILITY_FLAKY_RETRY_ENABLED" => "0",
      "DD_CIVISIBILITY_EARLY_FLAKE_DETECTION_ENABLED" => "0",
      "DD_TEST_MANAGEMENT_ENABLED" => "0",
      "DD_INSTRUMENTATION_TELEMETRY_ENABLED" => "0"
    }
  end

  def start_backend(run: nil, target_suite: nil)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      loop do
        socket = server.accept
        request_line = socket.gets
        headers = {}

        while (line = socket.gets) && line != "\r\n"
          name, value = line.split(":", 2)
          headers[name.downcase] = value.strip
        end

        socket.read(headers.fetch("content-length", "0").to_i)
        path = request_line.split.fetch(1)
        payload = backend_payload(path, run: run, target_suite: target_suite)

        socket.write(
          "HTTP/1.1 200 OK\r\n" \
          "Content-Type: application/json\r\n" \
          "Content-Length: #{payload.bytesize}\r\n" \
          "Connection: close\r\n\r\n" \
          "#{payload}"
        )
        socket.close
      rescue IOError, Errno::EBADF
        break
      end
    end

    [server, thread, "http://127.0.0.1:#{server.local_address.ip_port}"]
  end

  def backend_payload(path, run:, target_suite:)
    response = case path
    when Datadog::CI::Ext::Transport::DD_API_SETTINGS_PATH
      {
        "data" => {
          "id" => "parallel-tests-settings",
          "type" => Datadog::CI::Ext::Transport::DD_API_SETTINGS_TYPE,
          "attributes" => {
            "itr_enabled" => false,
            "code_coverage" => false,
            "tests_skipping" => false,
            "require_git" => false,
            "flaky_test_retries_enabled" => run == "B",
            "known_tests_enabled" => false,
            "impacted_tests_enabled" => false,
            "coverage_report_upload_enabled" => false,
            "early_flake_detection" => {"enabled" => false},
            "test_management" => {
              "enabled" => !run.nil?,
              "attempt_to_fix_retries" => 0
            }
          }
        }
      }
    when Datadog::CI::Ext::Transport::DD_API_TEST_MANAGEMENT_TESTS_PATH
      suites = if run == "A"
        {
          target_suite => {
            "tests" => {
              "always fails" => {
                "properties" => {
                  "disabled" => false,
                  "quarantined" => true,
                  "attempt_to_fix" => false
                }
              }
            }
          }
        }
      else
        {}
      end

      {
        "data" => {
          "id" => "parallel-tests-management",
          "type" => Datadog::CI::Ext::Transport::DD_API_TEST_MANAGEMENT_TESTS_TYPE,
          "attributes" => {"modules" => {"rspec" => {"suites" => suites}}}
        }
      }
    else
      {}
    end

    JSON.generate(response)
  end

  def accept_worker(server)
    socket = Timeout.timeout(30) { server.accept }
    worker, pid = Timeout.timeout(30) { socket.gets&.chomp }.split(",")
    [worker, pid.to_i, socket]
  end

  def wait_for_process_exit(pid)
    Timeout.timeout(30) do
      loop do
        Process.kill(0, pid)
        sleep(0.01)
      rescue Errno::ESRCH
        break
      end
    end
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  it "does not mix settings and test management state between concurrent invocations sharing TMPDIR" do
    Dir.mktmpdir("dd-ci-parallel-tests-collision", "/tmp") do |root|
      shared_tmpdir = File.join(root, "tmp")
      FileUtils.mkdir_p(shared_tmpdir)
      suite_a, target_a = write_suite(root, run: "A", failing: true)
      suite_b, = write_suite(root, run: "B")
      worker_barrier = write_worker_barrier(root)

      barrier_path = File.join(root, "barrier.sock")
      server = UNIXServer.new(barrier_path)
      backend_a, backend_thread_a, backend_url_a = start_backend(
        run: "A",
        target_suite: "CollisionRunA at #{target_a}"
      )
      backend_b, backend_thread_b, backend_url_b = start_backend(run: "B")

      run_a = start_parallel_run(
        run_environment(root, shared_tmpdir, barrier_path, "A", worker_barrier, backend_url_a),
        suite_a
      )
      barriers_a = 2.times.map { accept_barrier(server, "A") }

      run_b = start_parallel_run(
        run_environment(root, shared_tmpdir, barrier_path, "B", worker_barrier, backend_url_b),
        suite_b
      )
      barriers_b = 2.times.map { accept_barrier(server, "B") }

      barriers_a.each { |barrier| barrier.puts("continue") }
      status_a, stdout_a, stderr_a = finish_parallel_run(run_a)
      barriers_b.each { |barrier| barrier.puts("continue") }
      status_b, stdout_b, stderr_b = finish_parallel_run(run_b)

      aggregate_failures do
        expect(status_a).to be_success, "Run A failed:\n#{stdout_a}\n#{stderr_a}"
        expect(File.readlines(File.join(root, "run-a-executions")).size).to eq(1)
        expect(status_b).to be_success, "Run B failed:\n#{stdout_b}\n#{stderr_b}"
      end
    ensure
      barriers_a&.each(&:close)
      barriers_b&.each(&:close)
      server&.close
      terminate_parallel_run(run_a)
      terminate_parallel_run(run_b)
      backend_a&.close
      backend_b&.close
      backend_thread_a&.join(5)
      backend_thread_b&.join(5)
    end
  end

  it "does not clean up namespaced state when one worker exits" do
    Dir.mktmpdir("dd-ci-parallel-tests-lifecycle", "/tmp") do |root|
      shared_tmpdir = File.join(root, "tmp")
      FileUtils.mkdir_p(shared_tmpdir)
      suite = write_lifecycle_suite(root)

      barrier_path = File.join(root, "barrier.sock")
      server = UNIXServer.new(barrier_path)
      backend, backend_thread, backend_url = start_backend
      run = start_parallel_run(lifecycle_environment(shared_tmpdir, barrier_path, backend_url), suite)

      workers = 2.times.map { accept_worker(server) }.to_h do |worker, pid, socket|
        [worker, {pid: pid, socket: socket}]
      end

      storage_root = File.join(shared_tmpdir, "datadog-ci-storage")
      namespace_dir = Timeout.timeout(30) do
        loop do
          namespace = Dir.children(storage_root).first if Dir.exist?(storage_root)
          candidate = File.join(storage_root, namespace) if namespace
          state_file = File.join(candidate, "dd-ci-remote_component_state.dat") if candidate
          break candidate if state_file && File.file?(state_file)

          sleep(0.01)
        end
      end

      workers.fetch("fast").fetch(:socket).puts("continue")
      wait_for_process_exit(workers.fetch("fast").fetch(:pid))

      expect(run.fetch(:wait_thread)).to be_alive
      expect(process_alive?(workers.fetch("slow").fetch(:pid))).to be(true)
      expect(File.directory?(namespace_dir)).to be(true)

      workers.fetch("slow").fetch(:socket).puts("continue")
      status, stdout, stderr = finish_parallel_run(run)

      expect(status).to be_success, "Run failed:\n#{stdout}\n#{stderr}"
      expect(File.exist?(namespace_dir)).to be(false)
    ensure
      workers&.each_value { |worker| worker.fetch(:socket).close }
      server&.close
      backend&.close
      backend_thread&.join(5)
      terminate_parallel_run(run)
    end
  end
end
