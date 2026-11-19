# frozen_string_literal: true

require "open3"

RSpec.describe "Legacy telemetry configuration" do
  let(:legacy) { Datadog::Core::Configuration::Settings.new }
  let(:environment) { {} }
  let(:settings) { Datadog::CI::Configuration::RuntimeSettings.new(environment: environment) }

  around do |example|
    ClimateControl.modify("DD_INSTRUMENTATION_TELEMETRY_ENABLED" => nil) { example.run }
  end

  it "keeps CI telemetry enabled when the tracer uses its development default" do
    expect(legacy.telemetry.enabled).to be(false)
    expect(legacy.telemetry.using_default?(:enabled)).to be(true)
    settings.import_legacy!(legacy)

    expect(settings.telemetry.enabled).to be(true)
    expect(legacy.telemetry.enabled).to be(false)
  end

  it "honors an explicit legacy false value" do
    legacy.telemetry.enabled = false
    expect(legacy.telemetry.using_default?(:enabled)).to be(false)
    settings.import_legacy!(legacy)

    expect(settings.telemetry.enabled).to be(false)
  end

  it "honors an explicit legacy true value" do
    legacy.telemetry.enabled = true
    settings.import_legacy!(legacy)

    expect(settings.telemetry.enabled).to be(true)
  end

  it "honors the environment setting that disables telemetry" do
    ClimateControl.modify("DD_INSTRUMENTATION_TELEMETRY_ENABLED" => "false") do
      environment["DD_INSTRUMENTATION_TELEMETRY_ENABLED"] = "false"
      settings.import_legacy!(legacy)

      expect(legacy.telemetry.using_default?(:enabled)).to be(false)
      expect(settings.telemetry.enabled).to be(false)
    end
  end

  it "keeps an independent environment setting when legacy configuration uses its default" do
    environment["DD_INSTRUMENTATION_TELEMETRY_ENABLED"] = "false"
    settings.import_legacy!(legacy)

    expect(settings.telemetry.enabled).to be(false)
  end

  it "preserves explicit native false before a legacy true value" do
    settings.telemetry.enabled = false
    legacy.telemetry.enabled = true
    settings.import_legacy!(legacy)

    expect(settings.telemetry.enabled).to be(false)
  end

  it "returns to the CI default when the legacy option is reset" do
    legacy.telemetry.enabled = false
    settings.import_legacy!(legacy)
    expect(settings.telemetry.enabled).to be(false)
    legacy.telemetry.reset_option(:enabled)
    settings.import_legacy!(legacy)

    expect(legacy.telemetry.using_default?(:enabled)).to be(true)
    expect(settings.telemetry.enabled).to be(true)
  end

  it "sends CI telemetry in a real development process without enabling tracer telemetry" do
    output, status = Open3.capture2e(
      {"DD_INSTRUMENTATION_TELEMETRY_ENABLED" => nil}, RbConfig.ruby, "-Ilib", "-e", <<~RUBY
        require "socket"
        require "json"
        require "webmock"
        WebMock.enable!
        WebMock.disable_net_connect!
        require "datadog/ci"
        abort "not a development process" unless Datadog::Core::Environment::Execution.development?
        abort "tracer telemetry default changed" if Datadog.configuration.telemetry.enabled

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
            requests << JSON.parse(connection.read(length))
            connection.write("HTTP/1.1 200 OK\\r\\nContent-Length: 2\\r\\nConnection: close\\r\\n\\r\\n{}")
            connection.close
          end
        end
        begin
          Datadog.configure do |configuration|
            configuration.remote.enabled = false
            configuration.api_key = "test-key"
            configuration.ci.enabled = true
            configuration.ci.agentless_mode_enabled = true
            configuration.ci.git_metadata_upload_enabled = false
            configuration.ci.itr_enabled = false
            configuration.telemetry.agentless_url_override = "http://127.0.0.1:" + server.addr[1].to_s
          end
          telemetry = Datadog::CI.components.telemetry
          abort "CI telemetry is disabled" unless telemetry.enabled?
          telemetry.inc("civisibility", "events", 1)
          Datadog::CI.shutdown!
          collected = []
          collected << requests.pop until requests.empty?
          abort "CI metrics were not delivered" unless collected.any? { |payload| payload["request_type"] == "generate-metrics" }
          abort "tracer telemetry was enabled" if Datadog.configuration.telemetry.enabled
        ensure
          Datadog::CI.shutdown!
          Datadog.shutdown!
          listener.kill
          listener.join
          server.close
        end
      RUBY
    )
    expect(status.success?).to be(true), output
  end
end
