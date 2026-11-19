# frozen_string_literal: true

require "socket"
require "json"
require "msgpack"
require "net/http"
require "stringio"
require "zlib"

ENV.keys.grep(/\ADD_/).each { |key| ENV.delete(key) }
ENV["DD_INSTRUMENTATION_TELEMETRY_ENABLED"] = "false"
require "datadog/ci"

class BootstrapTraceIntake
  attr_reader :port

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @requests = Queue.new
    @thread = Thread.new do
      loop do
        socket = @server.accept
        path = socket.gets.split[1]
        headers = {}
        while (line = socket.gets) && line != "\r\n"
          key, value = line.split(":", 2)
          headers[key.downcase] = value.strip
        end
        body = socket.read(headers.fetch("content-length", "0").to_i)
        body = Zlib::GzipReader.new(StringIO.new(body)).read if headers["content-encoding"] == "gzip"
        @requests << {"path" => path, "body" => body, "headers" => headers}
        socket.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
        socket.close
      end
    end
  end

  def url
    "http://127.0.0.1:" + port.to_s
  end

  def close
    @thread.kill
    @thread.join
    @server.close
  end

  def drain
    rows = []
    rows << @requests.pop until @requests.empty?
    rows
  end
end

ci = BootstrapTraceIntake.new
replacement = BootstrapTraceIntake.new
apm = BootstrapTraceIntake.new
mode = ARGV.fetch(0)
result = {}
configure = lambda do |service|
  Datadog.configure do |c|
    c.service = service
    c.env = "initial-env"
    c.tags = {"custom" => "initial-tag"}
    c.api_key = "initial-key"
    c.site = "datadoghq.com"
    c.agent.host = "127.0.0.1"
    c.agent.port = apm.port
    c.telemetry.enabled = false
    c.diagnostics.startup_logs.enabled = false
    c.remote.enabled = false
    c.tracing.instrument :http
    c.ci.enabled = mode != "disabled"
    c.ci.agentless_mode_enabled = true
    c.ci.agentless_url = ci.url
    c.ci.git_metadata_upload_enabled = false
    c.ci.itr_enabled = false
  end
end

begin
  configure.call("initial-service")
  Net::HTTP.get(URI(ci.url + "/boot"))
  original = Datadog::CI.components(allow_initialization: false)
  result["ci_initialized"] = !original.nil?

  case mode
  when "direct_changes"
    Datadog.configuration.service = "updated-service"
    Datadog.configuration.env = "updated-env"
    Datadog.configuration.api_key = "updated-key"
    Datadog.configuration.tags["custom"] = "updated-tag"
    Datadog.configuration.ci.agentless_url = replacement.url
    session = Datadog::CI.start_test_session
    test_module = Datadog::CI.start_test_module("module")
    suite = Datadog::CI.start_test_suite("suite")
    test = Datadog::CI.start_test("example", "suite")
    result["session_service"] = session.service
    result["session_env"] = session.get_tag("env")
    result["session_tag"] = session.get_tag("custom")
    result["test_service"] = test.service
    result["generation_replaced"] = !Datadog::CI.components.equal?(original)
    test.passed!
    test.finish
    suite.finish
    test_module.finish
    session.finish
  when "disable_before_session"
    Datadog.configuration.ci.enabled = false
    result["session_started"] = !Datadog::CI.start_test_session.nil?
    Net::HTTP.get(URI(ci.url + "/after-disable"))
  when "shutdown"
    Datadog::CI.shutdown!
    Net::HTTP.get(URI(ci.url + "/after-shutdown"))
    result["generation_replaced"] = !Datadog::CI.components(allow_initialization: false).equal?(original)
  when "reconfigure"
    Datadog.send(:reset!)
    configure.call("reconfigured-service")
    Net::HTTP.get(URI(ci.url + "/after-reset"))
    session = Datadog::CI.start_test_session
    result["session_service"] = session.service
    session.finish
  end

  Datadog::CI.shutdown!
  Datadog.shutdown!
  ci_events = ci.drain.select { |request| request["path"] == "/api/v2/citestcycle" }
    .flat_map { |request| MessagePack.unpack(request["body"]).fetch("events") }
  result["initial_spans"] = ci_events.select { |event| event["type"] == "span" }.map { |event| event.dig("content", "name") }
  result["boot_spans"] = ci_events.select { |event| event["type"] == "span" }.map { |event| event["content"] }
  result["apm_paths"] = apm.drain.map { |request| request["path"] }
  replacement_requests = replacement.drain.select { |request| request["path"] == "/api/v2/citestcycle" }
  result["replacement_keys"] = replacement_requests.map { |request| request["headers"]["dd-api-key"] }.uniq
  result["replacement_tests"] = replacement_requests.flat_map { |request| MessagePack.unpack(request["body"]).fetch("events") }
    .select { |event| event["type"] == "test" }.map { |event| event["content"] }
  puts JSON.generate(result)
ensure
  Datadog::CI.shutdown!
  Datadog.shutdown!
  ci.close
  replacement.close
  apm.close
end
