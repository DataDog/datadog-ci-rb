# frozen_string_literal: true

require "datadog"
require "datadog/ci/configuration/extensions"
require "datadog/ci/tracer_bridge/component"
require "webmock/rspec"

RSpec.describe Datadog::CI::Configuration::Extensions do
  let(:ci_settings) { double(:ci_settings) }
  let(:settings) { double(:independent_settings, ci: ci_settings) }
  let(:application_writer) do
    writer = Datadog::Tracing::Writer.new(transport: double(:application_transport))
    allow(writer).to receive(:write)
    allow(writer).to receive(:stop)
    writer
  end
  let(:ci_writer) { instance_double(Datadog::Tracing::Writer, write: nil, stop: nil) }
  let(:bridge) { Datadog::CI::TracerBridge::Component.new(writer: ci_writer, logger: Logger.new(File::NULL)) }
  let(:components) { double(:independent_components, tracer_bridge: bridge) }

  before do
    WebMock.enable!
    allow(Datadog::CI).to receive(:configuration).and_return(settings)
    allow(Datadog::CI).to receive(:configuration_changed!)
    allow(Datadog::CI).to receive(:components).with(allow_initialization: false).and_return(components)
    described_class.activate!
    Datadog.configure do |c|
      c.telemetry.enabled = false
      c.remote.enabled = false
      c.tracing.writer = application_writer
    end
  end

  after do
    bridge.shutdown!
    Datadog.send(:reset!)
  end

  it "exposes the independent CI settings through the existing configuration API" do
    expect(Datadog.configuration.ci).to equal(ci_settings)
    Datadog.configure { |c| expect(c.ci).to equal(ci_settings) }
  end

  it "imports the latest legacy settings through the explicit importer" do
    Datadog.configure { |c| c.service = "latest-service" }
    target = double(:independent_settings, import_legacy!: nil)

    described_class.import_configuration!(target)

    expect(target).to have_received(:import_legacy!).with(Datadog.configuration)
    expect(Datadog.configuration.service).to eq("latest-service")
  end

  it "does not import the independent configuration into itself" do
    source = Datadog.configuration
    expect(source).not_to receive(:import_legacy!)

    described_class.import_configuration!(source)
  end

  it "activates a later tracer before returning its configuration" do
    host = Module.new do
      define_singleton_method(:configuration) { :tracer_configuration }
    end
    host.singleton_class.prepend(described_class::LazyConfiguration)
    allow(described_class).to receive(:tracer_active?).and_return(false)
    expect(described_class).to receive(:activate!).and_call_original

    expect(host.configuration).to eq(:tracer_configuration)
  end

  it "allows the original tracer configuration block to execute" do
    Datadog.configure { |c| c.service = "application-service" }

    expect(Datadog.configuration.service).to eq("application-service")
    expect(Datadog::CI).to have_received(:configuration_changed!).at_least(:once)
  end

  it "does not initialize CI when the application asks for its tracer" do
    expect(Datadog::CI).not_to receive(:components)

    expect(Datadog::Tracing.active_trace).to be_nil
  end

  it "does not attach CI context when inspecting the active application trace" do
    bridge.on_test_started(Struct.new(:id, :trace_id).new(101, 202))
    tracer = Datadog.send(:components).tracer
    expect(tracer).to receive(:active_trace).once.and_return(nil)
    expect(tracer).not_to receive(:continue_trace!)

    expect(Datadog::Tracing.active_trace).to be_nil
  end

  it "preserves explicit trace continuation arguments and its block" do
    bridge.on_test_started(Struct.new(:id, :trace_id).new(101, 202))
    tracer = Datadog.send(:components).tracer
    digest = Datadog::Tracing::TraceDigest.new(trace_id: 303, span_id: 404)
    block = proc {}
    expect(tracer).to receive(:continue_trace!).with(digest) do |&received|
      expect(received).to equal(block)
      :continued
    end

    expect(Datadog::Tracing.continue_trace!(digest, &block)).to eq(:continued)
  end

  it "does not initialize a global trace while a separate tracer samples its spans" do
    bridge.on_test_started(Struct.new(:id, :trace_id).new(101, 202))
    tracer = Datadog::Tracing::Tracer.new(writer: application_writer)
    expect(Datadog::Profiling).to receive(:enabled?).once.and_return(false)

    2.times { tracer.trace("application.request") {} }

    expect(application_writer).to have_received(:write).twice
    expect(Datadog::Tracing.active_trace).to be_nil
  end

  it "preserves the caller context when tracing inside explicit continuation" do
    bridge.on_test_started(Struct.new(:id, :trace_id).new(101, 202))
    digest = Datadog::Tracing::TraceDigest.new(trace_id: 303, span_id: 404)

    Datadog::Tracing.continue_trace!(digest) do
      Datadog::Tracing.trace("application.request") do |span, trace|
        expect(trace.id).to eq(303)
        expect(span.parent_id).to eq(404)
      end
    end

    expect(ci_writer).to have_received(:write).once do |trace|
      expect(trace.id).to eq(303)
      expect(trace.spans.first.parent_id).to eq(404)
    end
  end

  it "preserves baggage set before the first application span" do
    bridge.on_test_started(Struct.new(:id, :trace_id).new(101, 202))
    Datadog::Tracing.baggage["user.id"] = "123"

    Datadog::Tracing.trace("application.request") do |_span, trace|
      expect(trace.to_digest.baggage).to eq("user.id" => "123")
    end
  end

  it "automatically routes a real HTTP integration span to the independent writer" do
    Datadog.configure { |c| c.tracing.instrument :http }
    test = Struct.new(:id, :trace_id).new(101, 202)
    stub_request(:get, "http://example.test/items").to_return(status: 200, body: "items")
    bridge.on_test_started(test)

    expect(Net::HTTP.get(URI("http://example.test/items"))).to eq("items")
    bridge.on_test_finished(test)

    expect(ci_writer).to have_received(:write).once do |trace|
      expect(trace.id).to eq(test.trace_id)
      expect(trace.spans.first.name).to eq("http.request")
      expect(trace.spans.first.parent_id).to eq(test.id)
    end
    expect(application_writer).not_to have_received(:write)
  end
end
