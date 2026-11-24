# frozen_string_literal: true

require "webmock/rspec"
require "socket"
require "datadog/ci/test_tracing/transport"

RSpec.describe "Application spans in Test Optimization intake" do
  include_context "CI mode activated"

  let(:application_writer) do
    writer = Datadog::Tracing::Writer.new(transport: double(:application_transport))
    allow(writer).to receive(:write)
    allow(writer).to receive(:stop)
    writer
  end
  let(:api) { spy(:api) }
  let(:transport) { Datadog::CI::TestTracing::Transport.new(api: api, dd_env: "ci") }

  before do
    Datadog.configure do |c|
      c.service = "configured-service"
      c.tracing.writer = application_writer
      c.tracing.instrument :http
    end
    stub_request(:get, "http://example.test/items").to_return(status: 200, body: "items")
  end

  def serialized_events
    transport.send_events(traces)
    payloads = []
    expect(api).to have_received(:citestcycle_request).at_least(:once) do |args|
      expect(args[:path]).to eq("/api/v2/citestcycle")
      payloads << MessagePack.unpack(args[:payload])
    end
    payloads.flat_map { |payload| payload["events"] }
  end

  it "sends real integration spans and test events together through tracer reset" do
    original_test_mode = Datadog.configuration.tracing.test_mode.enabled
    original_trace_ids = Datadog.configuration.tracing.trace_id_128_bit_generation_enabled
    session = Datadog::CI.start_test_session
    test_module = Datadog::CI.start_test_module("module")
    suite = Datadog::CI.start_test_suite("suite")
    test = Datadog::CI.start_test("request", "suite")

    expect(Net::HTTP.get(URI("http://example.test/items"))).to eq("items")
    Datadog.send(:reset!)
    Datadog.configure do |c|
      c.tracing.writer = application_writer
      c.tracing.instrument :http
    end
    expect(Net::HTTP.get(URI("http://example.test/items"))).to eq("items")
    test.passed!
    test.finish
    suite.finish
    test_module.finish
    session.finish

    events = serialized_events
    application_spans = events.select { |event| event["type"] == "span" }.map { |event| event["content"] }
    expect(application_spans.size).to eq(2)
    application_spans.each do |span|
      expect(span).to include("name" => "http.request", "parent_id" => test.id, "trace_id" => test.trace_id)
      expect(span["meta"]).to include("_dd.origin" => "ciapp-test")
    end
    expect(events.count { |event| event["type"] == "test" }).to eq(1)
    expect(session.service).to eq("configured-service")
    expect(application_writer).not_to have_received(:write)
    expect(Datadog.configuration.tracing.test_mode.enabled).to eq(original_test_mode)
    expect(Datadog.configuration.tracing.trace_id_128_bit_generation_enabled).to eq(original_trace_ids)
  end

  it "serializes 128-bit application trace IDs without mutating the application trace" do
    session = Datadog::CI.start_test_session
    trace_id = (0x123456789abcdef0 << 64) | 42
    digest = Datadog::Tracing::TraceDigest.new(trace_id: trace_id, span_id: 101)
    Datadog::Tracing.trace("external", continue_from: digest) {}
    session.finish

    application_trace = traces.find { |trace| trace.spans.any? { |span| span.name == "external" } }
    original_tags = application_trace.spans.first.meta.dup
    event = serialized_events.find { |entry| entry["type"] == "span" }

    expect(event["content"]["trace_id"]).to eq(42)
    expect(event["content"]["meta"]["_dd.p.tid"]).to eq("123456789abcdef0")
    expect(event["content"]["meta"]["_dd.origin"]).to eq("")
    expect(application_trace.origin).to be_nil
    expect(original_tags).not_to have_key("_dd.origin")
    expect(application_trace.id).to eq(trace_id)
    expect(application_trace.spans.first.meta).to eq(original_tags)
    expect(application_writer).not_to have_received(:write)
  end

  it "does not trace internal intake HTTP requests during an active test" do
    server = TCPServer.new("127.0.0.1", 0)
    received = Queue.new
    listener = Thread.new do
      connection = server.accept
      headers = []
      while (line = connection.gets) && line != "\r\n"
        headers << line
      end
      received << headers
      connection.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
    ensure
      connection&.close
    end
    session = Datadog::CI.start_test_session
    test = Datadog::CI.start_test("intake", "suite")
    client = Datadog::CI::Transport::HTTP.new(host: "127.0.0.1", port: server.addr[1], ssl: false, timeout: 2)

    response = client.request(path: "/info", payload: "", headers: {}, verb: "get", retries: 0)

    expect(response).to be_ok
    expect(listener.join(3)).to eq(listener)
    expect(received.pop.join.downcase).to include("dd-internal-untraced-request: 1")
    test.passed!
    test.finish
    session.finish
    expect(traces.flat_map(&:spans).map(&:name)).not_to include("http.request")
    expect(application_writer).not_to have_received(:write)
  ensure
    server&.close
    listener&.kill if listener&.alive?
    listener&.join
  end
end
