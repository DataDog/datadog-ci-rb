# frozen_string_literal: true

require "datadog"
require "datadog/tracing/tracer"
require "datadog/ci/tracer_bridge/component"
require "datadog/ci/tracer_bridge/null_component"

RSpec.describe Datadog::CI::TracerBridge::Component do
  let(:application_writer) { instance_double(Datadog::Tracing::Writer, write: nil, stop: nil) }
  let(:ci_writer) { instance_double(Datadog::Tracing::Writer, write: nil, stop: nil) }
  let(:logger) { Logger.new(File::NULL) }
  let(:tracer) { Datadog::Tracing::Tracer.new(writer: application_writer, logger: logger) }
  let(:parent_class) { Struct.new(:id, :trace_id) }
  let(:test) { parent_class.new(101, 202) }
  let(:session) { parent_class.new(303, 404) }
  let(:bridge) { described_class.new(writer: ci_writer, logger: logger) }

  after { bridge.shutdown! }

  def trace_application(name = "http.request")
    bridge.observe(tracer)
    tracer.trace(name, service: "http-client", type: "http") {}
  end

  it "routes integration spans to CI with the test parent and no APM duplicate" do
    bridge.on_test_started(test)
    trace_application

    expect(ci_writer).to have_received(:write).once do |trace|
      expect(trace.id).to eq(test.trace_id)
      expect(trace.origin).to eq("ciapp-test")
      expect(trace.spans.map(&:parent_id)).to eq([test.id])
    end
    expect(application_writer).not_to have_received(:write)
  end

  it "links successive completed application traces to the same test" do
    bridge.on_test_started(test)
    2.times { trace_application }

    expect(ci_writer).to have_received(:write).twice do |trace|
      expect(trace.id).to eq(test.trace_id)
      expect(trace.spans.first.parent_id).to eq(test.id)
    end
  end

  it "restores application context after the test" do
    outer = tracer.trace("outer")
    original = tracer.active_trace
    bridge.on_test_started(test)
    trace_application
    bridge.on_test_finished(test)

    expect(tracer.active_trace).to equal(original)
    outer.finish
    expect(application_writer).to have_received(:write).once
  end

  it "delegates non-CI traces after the test finishes" do
    bridge.on_test_started(test)
    trace_application
    bridge.on_test_finished(test)
    trace_application("application.work")

    expect(ci_writer).to have_received(:write).once
    expect(application_writer).to have_received(:write).once
  end

  it "does not stop the independent CI writer when the tracer shuts down" do
    bridge.on_test_started(test)
    bridge.observe(tracer)
    tracer.shutdown!

    expect(application_writer).to have_received(:stop).once
    expect(ci_writer).not_to have_received(:stop)
  end

  it "attaches a replacement tracer during the same test" do
    bridge.on_test_started(test)
    trace_application
    replacement = Datadog::Tracing::Tracer.new(writer: application_writer, logger: logger)
    bridge.observe(replacement)
    replacement.trace("replacement.request") {}

    expect(ci_writer).to have_received(:write).twice do |trace|
      expect(trace.spans.first.parent_id).to eq(test.id)
    end
  end

  it "routes setup and teardown spans during the session" do
    bridge.on_session_started(session)
    trace_application
    bridge.on_test_started(test)
    trace_application
    bridge.on_test_finished(test)
    trace_application
    bridge.on_session_finished(session)

    expect(ci_writer).to have_received(:write).exactly(3).times
    expect(application_writer).not_to have_received(:write)
  end

  it "parents integration spans to the active CI step" do
    step = parent_class.new(505, test.trace_id)
    bridge.on_test_started(test)
    bridge.on_span_started(step)
    trace_application
    bridge.on_span_finished(step)
    trace_application

    expect(ci_writer).to have_received(:write).with(have_attributes(spans: [have_attributes(parent_id: step.id)]))
    expect(ci_writer).to have_received(:write).with(have_attributes(spans: [have_attributes(parent_id: test.id)]))
  end

  it "routes explicitly continued spans that finish after their CI session" do
    bridge.on_session_started(session)
    bridge.observe(tracer)
    digest = Datadog::Tracing::TraceDigest.new(trace_id: 707, span_id: 808)
    application_span = tracer.trace("delayed.request", continue_from: digest)
    bridge.on_session_finished(session)
    application_span.finish

    expect(ci_writer).to have_received(:write).once do |trace|
      expect(trace.id).to eq(707)
      expect(trace.origin).to be_nil
    end
    expect(application_writer).not_to have_received(:write)
  end

  it "restores application delivery when the CI runtime shuts down" do
    bridge.on_session_started(session)
    trace_application
    bridge.on_session_finished(session)
    bridge.shutdown!
    trace_application("application.work")

    expect(ci_writer).to have_received(:write).once
    expect(application_writer).to have_received(:write).once
  end

  it "does not wrap the writer when disabled" do
    disabled = described_class.new(writer: ci_writer, logger: logger, enabled: false)
    disabled.on_test_started(test)
    disabled.observe(tracer)

    expect(tracer.writer).to equal(application_writer)
    expect(tracer.active_trace).to be_nil
  end

  it "logs forwarding failures without raising into the application" do
    allow(ci_writer).to receive(:write).and_raise(IOError, "closed")
    allow(logger).to receive(:warn)
    bridge.on_test_started(test)

    expect { trace_application }.not_to raise_error
    expect(logger).to have_received(:warn).with(/Failed to send application spans: IOError: closed/)
    expect(application_writer).not_to have_received(:write)
  end

  it "contains forwarding failures when a custom logger also fails" do
    allow(ci_writer).to receive(:write).and_raise(IOError, "closed")
    allow(logger).to receive(:warn).and_raise(IOError, "logger closed")
    bridge.on_test_started(test)
    trace = Datadog::Tracing::TraceSegment.new([], origin: "ciapp-test")

    expect(bridge.write(trace)).to be(true)
    expect(logger).to have_received(:warn)
  end

  it "contains context failures when a custom logger also fails" do
    allow(tracer).to receive(:provider).and_raise(IOError, "context unavailable")
    allow(logger).to receive(:warn).and_raise(IOError, "logger closed")
    bridge.on_test_started(test)

    expect { bridge.observe(tracer) }.not_to raise_error
    expect(logger).to have_received(:warn)
  end

  it "preserves exceptions from customer code" do
    bridge.on_test_started(test)
    bridge.observe(tracer)
    error = RuntimeError.new("customer failure")

    expect { tracer.trace("customer") { raise error } }.to raise_error { |raised| expect(raised).to equal(error) }
  end

  it "does not wrap a tracer more than once" do
    bridge.on_test_started(test)
    bridge.observe(tracer)
    writer = tracer.writer
    bridge.observe(tracer)

    expect(tracer.writer).to equal(writer)
  end

  it "can replace a retired bridge without retaining its writer wrapper" do
    bridge.on_test_started(test)
    bridge.observe(tracer)
    bridge.shutdown!
    replacement = described_class.new(writer: ci_writer, logger: logger)
    replacement.on_test_started(test)
    replacement.observe(tracer)
    tracer.trace("replacement.request") {}
    replacement.shutdown!

    expect(ci_writer).to have_received(:write).once
  end
end
