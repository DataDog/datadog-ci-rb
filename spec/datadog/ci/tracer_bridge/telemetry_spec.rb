# frozen_string_literal: true

require "open3"

RSpec.describe "Optional tracer telemetry with WebMock" do
  [true, false].product([true, false]).each do |webmock_first, agentless|
    it "sends #{agentless ? "agentless" : "agent"} telemetry when WebMock loads #{webmock_first ? "before" : "after"} CI" do
      output, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", <<~RUBY)
        require "socket"
        require "json"
        require "timeout"
        #{'require "webmock"' if webmock_first}
        require "datadog/ci"
        require "webmock"
        WebMock.enable!
        WebMock.disable_net_connect!

        server = TCPServer.new("127.0.0.1", 0)
        requests = Queue.new
        listener = Thread.new do
          loop do
            connection = server.accept
            headers = []
            while (line = connection.gets) && line != "\\r\\n"
              headers << line
            end
            length = headers.find { |header| header.downcase.start_with?("content-length:") }.split(":", 2).last.to_i
            requests << [headers.first, JSON.parse(connection.read(length))]
            connection.write("HTTP/1.1 200 OK\\r\\nContent-Length: 2\\r\\nConnection: close\\r\\n\\r\\n{}")
            connection.close
          end
        end

        begin
          Datadog.configure do |c|
            c.agent.host = "127.0.0.1"
            c.agent.port = server.addr[1]
            c.remote.enabled = false
            c.tracing.enabled = false
            c.telemetry.enabled = true
            c.telemetry.agentless_enabled = #{agentless}
            c.telemetry.agentless_url_override = "http://127.0.0.1:" + server.addr[1].to_s
            c.api_key = "test-api-key"
            c.telemetry.heartbeat_interval_seconds = 123
            c.telemetry.metrics_aggregation_interval_seconds = 0.01
            c.telemetry.shutdown_timeout_seconds = 2
          end
          first_request = Timeout.timeout(5) { requests.pop }
          abort "CI runtime started before the session" if Datadog::CI.components(allow_initialization: false)
          settings = Datadog.configuration.telemetry
          abort "Telemetry settings changed" unless settings.enabled && settings.agentless_enabled == #{agentless} && settings.heartbeat_interval_seconds == 123

          begin
            Net::HTTP.get(URI("http://example.test/customer"))
            abort "Customer HTTP bypassed WebMock"
          rescue WebMock::NetConnectNotAllowedError
          end
          WebMock.stub_request(:get, "http://example.test/customer").to_return(body: "stubbed")
          abort "Customer stub failed" unless Net::HTTP.get(URI("http://example.test/customer")) == "stubbed"

          Datadog.shutdown!
          collected = [first_request]
          collected << requests.pop until requests.empty?
          abort "No telemetry was delivered" if collected.empty?
          abort "Telemetry used the wrong intake" unless collected.all? { |path, _| path.include?(#{(agentless ? "/api/v2/apmtelemetry" : "/telemetry/proxy/api/v2/apmtelemetry").inspect}) }
          abort "App start was not delivered" unless collected.any? { |_, payload| payload["request_type"] == "app-started" }
        ensure
          Datadog.shutdown!
          listener.kill
          listener.join
          server.close
        end
      RUBY

      expect(status.success?).to be(true), output
      expect(output).not_to include("terminated with exception", "WebMock::NetConnectNotAllowedError")
    end
  end
end
