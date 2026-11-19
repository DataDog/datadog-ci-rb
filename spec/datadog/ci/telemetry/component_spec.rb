# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/telemetry/component"

RSpec.describe Datadog::CI::Telemetry::Component do
  let(:requests) { [] }
  let(:logger) { double(:logger, warn: nil) }
  let(:response) { double(:response, ok?: true, code: 200) }
  let(:client) { double(:client) }
  let(:agentless) { true }
  let(:api_key) { "test-key" }
  let(:enabled) { true }
  let(:buffer_size) { 100 }
  let(:telemetry) do
    described_class.new(
      client: client, logger: logger, application: {tracer_version: "1.0.0", service_name: "tests"},
      host: {hostname: "host"}, runtime_id_provider: -> { "runtime" }, agentless: agentless,
      api_key: api_key, enabled: enabled, aggregation_interval: 60.0, buffer_size: buffer_size
    )
  end

  before do
    allow(client).to receive(:call) do |**request|
      requests << request.merge(body: JSON.parse(request[:payload]))
      response
    end
  end

  after { telemetry.shutdown! }

  def metric_payloads
    requests.map { |request| request[:body] }.select { |body| body["request_type"] == "generate-metrics" }
  end

  it "aggregates counts and sends the telemetry v2 envelope" do
    telemetry.inc("civisibility", "events", 2, tags: {framework: "rspec", type: "test"})
    telemetry.inc("civisibility", "events", 3, tags: {type: "test", framework: "rspec"})
    telemetry.flush

    expect(requests.map { |request| request[:body]["request_type"] }).to eq(%w[app-started generate-metrics])
    body = metric_payloads.first
    expect(body).to include("api_version" => "v2", "runtime_id" => "runtime", "seq_id" => 2)
    expect(body["application"]).to include("tracer_version" => "1.0.0", "service_name" => "tests")
    metric = body["payload"]["series"].first
    expect(metric).to include("metric" => "events", "type" => "count", "tags" => ["framework:rspec", "type:test"], "common" => true)
    expect(metric["points"].first.last).to eq(5)
    expect(requests.last[:path]).to eq("/api/v2/apmtelemetry")
    expect(requests.last[:headers]).to include("DD-API-KEY" => "test-key", "DD-Telemetry-Request-Type" => "generate-metrics")
  end

  it "retains individual distribution values" do
    telemetry.distribution("civisibility", "duration", 1.5, tags: ["framework:rspec"])
    telemetry.distribution("civisibility", "duration", 2.5, tags: ["framework:rspec"])
    telemetry.flush
    body = requests.last[:body]
    expect(body["request_type"]).to eq("distributions")
    expect(body["payload"]["series"]).to eq([
      {"metric" => "duration", "tags" => ["framework:rspec"], "common" => true, "points" => [1.5, 2.5]}
    ])
  end

  context "with an agent" do
    let(:agentless) { false }

    it "uses the telemetry proxy without sending an API key" do
      telemetry.inc("civisibility", "events", 1)
      telemetry.flush
      expect(requests.last[:path]).to eq("/telemetry/proxy/api/v2/apmtelemetry")
      expect(requests.last[:headers]).not_to have_key("DD-API-KEY")
    end
  end

  context "when telemetry is disabled" do
    let(:enabled) { false }

    it "does not send requests" do
      telemetry.inc("civisibility", "events", 1)
      telemetry.distribution("civisibility", "duration", 1.0)
      telemetry.flush
      telemetry.shutdown!
      expect(requests).to be_empty
    end
  end

  context "when the agentless API key is missing" do
    let(:api_key) { nil }

    it "keeps collection disabled" do
      expect(telemetry.enabled?).to be(false)
      telemetry.inc("civisibility", "events", 1)
      telemetry.flush
      expect(requests).to be_empty
    end
  end

  context "with a bounded buffer" do
    let(:buffer_size) { 2 }

    it "bounds distinct metrics but continues aggregating existing counts" do
      telemetry.inc("civisibility", "first", 1)
      telemetry.inc("civisibility", "second", 1)
      telemetry.inc("civisibility", "first", 2)
      expect(logger).to receive(:warn).with(/buffer is full/).once
      2.times { telemetry.inc("civisibility", "dropped", 1) }
      telemetry.flush
      series = metric_payloads.first["payload"]["series"]
      expect(series.map { |metric| metric["metric"] }).to eq(%w[first second])
      expect(series.first["points"].first.last).to eq(3)
    end

    it "bounds distribution samples" do
      3.times { |value| telemetry.distribution("civisibility", "duration", value) }
      telemetry.flush
      expect(requests.last[:body]["payload"]["series"].first["points"]).to eq([0, 1])
    end
  end

  it "does not raise transport failures into the test process" do
    allow(client).to receive(:call).and_raise(IOError, "closed")
    expect(logger).to receive(:warn).with(/closed/)
    telemetry.inc("civisibility", "events", 1)
    expect { telemetry.flush }.not_to raise_error
  end

  context "when the logger raises" do
    before { allow(logger).to receive(:warn).and_raise(IOError, "logger closed") }

    context "when the buffer is full" do
      let(:buffer_size) { 0 }

      it "drops metric samples without raising" do
        expect { telemetry.inc("civisibility", "events", 1) }.not_to raise_error
        expect { telemetry.distribution("civisibility", "duration", 1.5) }.not_to raise_error
        telemetry.flush
        expect(requests).to be_empty
      end
    end

    it "handles transport failures without raising" do
      allow(client).to receive(:call).and_raise(IOError, "connection closed")
      telemetry.inc("civisibility", "events", 1)
      expect { telemetry.flush }.not_to raise_error
    end

    it "continues metric uploads after an HTTP error" do
      allow(response).to receive(:ok?).and_return(false)
      allow(response).to receive(:code).and_return(500)
      telemetry.inc("civisibility", "events", 1)
      expect { telemetry.flush }.not_to raise_error
      expect(requests.map { |request| request[:body]["request_type"] }).to eq(%w[app-started generate-metrics])
    end
  end

  it "flushes and closes once at shutdown" do
    telemetry.inc("civisibility", "events", 1)
    2.times { telemetry.shutdown! }
    expect(requests.map { |request| request[:body]["request_type"] }).to eq(%w[app-started generate-metrics app-closing])
    expect(requests.map { |request| request[:body]["seq_id"] }).to eq([1, 2, 3])
  end

  it "stops collecting and sending after disable" do
    telemetry.inc("civisibility", "events", 1)
    telemetry.disable!
    telemetry.inc("civisibility", "events", 1)
    telemetry.flush
    telemetry.shutdown!
    expect(requests).to be_empty
  end
end
