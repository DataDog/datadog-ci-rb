# frozen_string_literal: true

require "open3"
require "tmpdir"
require "socket"
require "stringio"
require "zlib"

class StandaloneCIIntake
  attr_reader :url

  def initialize(coverage: false)
    @coverage = coverage
    @requests = []
    @mutex = Mutex.new
    @server = TCPServer.new("127.0.0.1", 0)
    @url = "http://127.0.0.1:#{@server.addr[1]}"
    @thread = Thread.new do
      loop do
        socket = @server.accept
        serve(socket)
        socket.close
      end
    rescue IOError, Errno::EBADF
      raise unless @server.closed?
    end
  end

  def requests
    @mutex.synchronize { @requests.dup }
  end

  def events
    requests.select { |request| request[:path] == "/api/v2/citestcycle" }
      .flat_map { |request| MessagePack.unpack(request[:body]).fetch("events") }
  end

  def stop
    @server.close
    @thread.join
  end

  private

  def serve(socket)
    path = socket.gets.split[1]
    headers = {}
    while (line = socket.gets) && line != "\r\n"
      name, value = line.split(":", 2)
      headers[name.downcase] = value.strip
    end
    body = socket.read(headers.fetch("content-length", "0").to_i)
    body = Zlib::GzipReader.new(StringIO.new(body)).read if headers["content-encoding"] == "gzip"
    @mutex.synchronize { @requests << {path: path, body: body} }
    response = JSON.generate(response_for(path))
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{response.bytesize}\r\nConnection: close\r\n\r\n#{response}")
  end

  def response_for(path)
    case path
    when "/api/v2/libraries/tests/services/setting"
      {data: {attributes: {
        itr_enabled: true, tests_skipping: true, code_coverage: @coverage,
        flaky_test_retries_enabled: true, require_git: false
      }}}
    when "/api/v2/ci/tests/skippable"
      {meta: {correlation_id: "standalone"}, data: [{type: "test", attributes: {
        name: "unaffected", suite: "Standalone at ./spec/standalone_spec.rb",
        parameters: JSON.generate(arguments: {}, metadata: {scoped_id: "1:2"})
      }}]}
    else
      {}
    end
  end
end

RSpec.describe "Standalone CI runtime" do
  let(:repository_root) { File.expand_path("../../..", __dir__) }
  let(:native_extension) do
    File.join(repository_root, "lib", "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}.#{RbConfig::CONFIG.fetch("DLEXT")}")
  end
  let(:coverage_enabled) { File.file?(native_extension) }
  let(:intake) { StandaloneCIIntake.new(coverage: coverage_enabled) }

  after { intake.stop }

  def run_child(environment, arguments, directory)
    Bundler.with_unbundled_env do
      Open3.popen2e(environment.merge("RUBYOPT" => nil), RbConfig.ruby, *arguments, chdir: directory) do |input, output, process|
        input.close
        reader = Thread.new { output.read }
        unless process.join(60)
          Process.kill("KILL", process.pid)
          process.join
          raise "Standalone subprocess timed out: #{reader.value}"
        end
        [reader.value, process.value]
      end
    end
  end

  def child_environment
    ENV.keys.grep(/\ADD_/).each_with_object({}) { |name, values| values[name] = nil }.merge(
      "DD_GIT_REPOSITORY_URL" => "https://example.test/standalone.git",
      "DD_GIT_COMMIT_SHA" => "a" * 40,
      "DD_INSTRUMENTATION_TELEMETRY_ENABLED" => "false"
    )
  end

  def configuration_script
    <<~RUBY
      Datadog.configure do |settings|
        settings.service = "standalone-tests"
        settings.api_key = "test-key"
        settings.telemetry.enabled = false
        settings.ci.enabled = true
        settings.ci.agentless_mode_enabled = true
        settings.ci.agentless_url = #{intake.url.inspect}
        settings.ci.git_metadata_upload_enabled = false
        settings.ci.itr_enabled = true
        settings.ci.itr_test_impact_analysis_use_allocation_tracing = false
        settings.ci.tia_static_dependencies_tracking_enabled = false
        settings.ci.retry_failed_tests_enabled = true
        settings.ci.retry_failed_tests_max_attempts = 2
      end
    RUBY
  end

  it "runs RSpec sessions, retries, TIA, and available native coverage without the tracer gem" do
    Dir.mktmpdir("standalone-ci") do |directory|
      gemfile = File.join(directory, "Gemfile")
      File.write(gemfile, <<~GEMFILE)
        source "https://rubygems.org"
        gem "datadog-ci", path: #{repository_root.inspect}
        gem "rspec", #{Gem.loaded_specs.fetch("rspec").version.to_s.inspect}
      GEMFILE
      environment = child_environment.merge("BUNDLE_GEMFILE" => gemfile)
      output, status = run_child(environment, ["-S", "bundle", "lock", "--local"], directory)
      expect(status.success?).to be(true), output
      expect(File.read("#{gemfile}.lock")).not_to match(/^    datadog \(/)

      Dir.mkdir(File.join(directory, "spec"))
      File.write(File.join(directory, "subject.rb"), "module StandaloneSubject; def self.value; 7; end; end\n")
      File.write(File.join(directory, "spec", "standalone_spec.rb"), <<~RUBY)
        require_relative "../subject"
        RSpec.describe "Standalone" do
          it "flaky" do
            raise "tracer loaded" if defined?(Datadog::Tracing)
            raise "subject failed" unless StandaloneSubject.value == 7
            $standalone_attempts ||= 0
            $standalone_attempts += 1
            raise "first attempt" if $standalone_attempts == 1
          end
          it "unaffected" do
            raise "TIA did not skip the example"
          end
        end
      RUBY
      File.write(File.join(directory, "run.rb"), <<~RUBY)
        require "bundler/setup"
        require "rspec/core"
        require "datadog/ci"
        abort "tracer gem available" if Bundler.load.specs.any? { |spec| spec.name == "datadog" }
        abort "tracer loaded" if defined?(Datadog::Tracing)
        #{configuration_script}
        Datadog.configure { |settings| settings.ci.instrument :rspec }
        result = RSpec::Core::Runner.run(["--options", File::NULL, "spec/standalone_spec.rb"])
        Datadog::CI.shutdown!
        abort "tracer loaded during tests" if defined?(Datadog::Tracing)
        exit result
      RUBY
      output, status = run_child(environment, ["run.rb"], directory)
      expect(status.success?).to be(true), output
    end

    events = intake.events
    expect(events.map { |event| event["type"] }).to include("test_session_end", "test_module_end", "test_suite_end")
    tests = events.select { |event| event["type"] == "test" }.map { |event| event.fetch("content") }
    flaky = tests.select { |test| test.dig("meta", "test.name") == "flaky" }
    expect(flaky.map { |test| test.dig("meta", "test.status") }).to eq(["fail", "pass"])
    expect(flaky.last.dig("meta", "test.is_retry")).to eq("true")
    skipped = tests.find { |test| test.dig("meta", "test.name") == "unaffected" }
    expect(skipped.fetch("meta")).to include("test.status" => "skip", "test.skipped_by_itr" => "true")
    expect(tests.map { |test| test["service"] }.uniq).to eq(["standalone-tests"])
    if coverage_enabled
      coverage = intake.requests.select { |request| request[:path] == "/api/v2/citestcov" }
      expect(coverage).not_to be_empty
      expect(coverage.map { |request| request[:body] }.join).to include("subject.rb")
    end
  end
  it "forwards integration spans when the tracer loads after an active CI session" do
    tracer_spec = Gem.loaded_specs.fetch("datadog")
    initial_load_paths = $LOAD_PATH.reject do |path|
      tracer_spec.full_require_paths.any? { |tracer_path| path.start_with?(tracer_path) }
    end
    Dir.mktmpdir("late-tracer-ci") do |directory|
      File.write(File.join(directory, "run.rb"), <<~RUBY)
        gem_home = Gem.dir
        gem_paths = Gem.path
        Gem.use_paths(#{File.join(directory, "empty-gems").inspect}, [])
        require "datadog/ci"
        abort "tracer loaded too early" if defined?(Datadog::Tracing)
        #{configuration_script}
        Datadog.configure { |settings| settings.ci.itr_enabled = false }
        session = Datadog::CI.start_test_session(tags: {"test.framework" => "manual"})
        test_module = Datadog::CI.start_test_module("manual")
        suite = Datadog::CI.start_test_suite("late")
        test = Datadog::CI.start_test("request", "late")
        components = Datadog::CI.components

        Gem.use_paths(gem_home, gem_paths)
        tracer_spec = Gem::Specification.load(#{tracer_spec.loaded_from.inspect})
        tracer_spec.full_gem_path = #{tracer_spec.full_gem_path.inspect}
        tracer_spec.extension_dir = #{tracer_spec.extension_dir.inspect}
        tracer_spec.activate
        require "datadog"
        Datadog.configure do |settings|
          settings.telemetry.enabled = false
          settings.remote.enabled = false
          settings.tracing.instrument :http
        end
        abort "CI components replaced" unless Datadog::CI.components.equal?(components)
        abort "CI session replaced" unless Datadog::CI.active_test_session.equal?(session)
        Net::HTTP.get(URI(#{(intake.url + "/application").inspect}))
        test.passed!
        test.finish
        suite.finish
        test_module.finish
        session.finish
        Datadog::CI.shutdown!
        Datadog.shutdown!
      RUBY
      output, status = run_child(
        child_environment,
        ["-I", initial_load_paths.join(File::PATH_SEPARATOR), "run.rb"],
        directory
      )
      expect(status.success?).to be(true), output
    end

    events = intake.events
    test = events.find { |event| event["type"] == "test" }.fetch("content")
    application_spans = events.select { |event| event["type"] == "span" }.map { |event| event.fetch("content") }
    expect(application_spans.size).to eq(1)
    expect(application_spans.first).to include(
      "name" => "http.request", "trace_id" => test["trace_id"], "parent_id" => test["span_id"]
    )
    expect(application_spans.first.fetch("meta")).to include("_dd.origin" => "ciapp-test")
  end
end
