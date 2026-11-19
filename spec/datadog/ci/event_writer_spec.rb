# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "datadog/ci/event_writer"
require "datadog/ci/event_tracer"

RSpec.describe Datadog::CI::EventWriter do
  let(:transport) { double(:transport, send_traces: []) }
  let(:logger) { double(:logger, warn: nil) }
  let(:writer) { described_class.new(transport: transport, logger: logger, flush_interval: 60, buffer_size: 2) }
  let(:trace) { double(:trace) }
  let(:sent) { Queue.new }
  let(:release_send) { Queue.new }

  before { use_real_tracer! }

  after { writer.shutdown! }

  it "sends the first event without waiting for the flush interval" do
    expect(transport).to receive(:send_traces).with([trace]).once { sent << true }
    expect(writer.write(trace)).to be(true)
    expect(Timeout.timeout(5) { sent.pop }).to be(true)
    expect(writer).to be_running
  end

  it "flushes accepted events once when shutdown follows the first write" do
    expect(transport).to receive(:send_traces).with([trace]).once
    expect(writer.write(trace)).to be(true)
    writer.shutdown!
    writer.shutdown!
  end

  it "logs transport errors without raising into the test" do
    allow(transport).to receive(:send_traces).and_raise(IOError, "connection closed")
    expect(logger).to receive(:warn).with(/connection closed/)
    writer.write(trace)
    expect { writer.flush }.not_to raise_error
  end

  context "while the first send is blocked" do
    before do
      allow(transport).to receive(:send_traces) do |events|
        sent << events
        release_send.pop if events == ["in flight"]
        []
      end
      writer.write("in flight")
      expect(Timeout.timeout(5) { sent.pop }).to eq(["in flight"])
    end

    after { release_send << true }

    it "limits buffered events without raising into the test" do
      2.times { expect(writer.write(trace)).to be(true) }
      expect(logger).to receive(:warn).with(/buffer is full/)
      expect(writer.write(trace)).to be(false)
      release_send << true
      writer.flush
      expect(Timeout.timeout(5) { sent.pop }).to eq([trace, trace])
      expect(sent).to be_empty
    end

    it "drains accepted events once during concurrent flush and shutdown" do
      writer.write("pending")
      flushing = Thread.new { writer.flush }
      expect(try_wait_until { flushing.status == "sleep" }).to be(true)
      stopping = Thread.new { writer.shutdown! }
      expect(try_wait_until { writer.stopped? }).to be(true)
      expect(writer.write("too late")).to be(false)
      release_send << true
      Timeout.timeout(5) do
        flushing.value
        stopping.value
      end
      writer.shutdown!
      expect(Timeout.timeout(5) { sent.pop }).to eq(["pending"])
      expect(sent).to be_empty
    ensure
      release_send << true
      flushing&.join(5)
      stopping&.join(5)
    end

    context "when the logger raises" do
      before { allow(logger).to receive(:warn).and_raise(IOError, "logger closed") }

      it "finishes event spans when the event buffer is full" do
        2.times { writer.write(trace) }
        tracer = Datadog::CI::EventTracer.new(writer: writer)
        span = tracer.trace("test")
        expect { span.finish }.not_to raise_error
        expect(span.finished?).to be(true)
        expect(tracer.active_span).to be_nil
      end

      it "preserves test exceptions when the event buffer is full" do
        2.times { writer.write(trace) }
        tracer = Datadog::CI::EventTracer.new(writer: writer)
        expect { tracer.trace("test") { raise "test failed" } }.to raise_error(RuntimeError, "test failed")
        expect(tracer.active_span).to be_nil
      end
    end
  end

  context "when the logger raises" do
    before { allow(logger).to receive(:warn).and_raise(IOError, "logger closed") }

    it "drops events from a full buffer without raising" do
      empty_writer = described_class.new(transport: transport, logger: logger, buffer_size: 0)
      expect(empty_writer.write(trace)).to be(false)
    ensure
      empty_writer&.shutdown!
    end

    it "handles transport failures without raising" do
      allow(transport).to receive(:send_traces).and_raise(IOError, "connection closed")
      writer.write(trace)
      expect { writer.flush }.not_to raise_error
    end
  end

  it "does not resend pending parent events from a forked worker" do
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    parent_pid = Process.pid
    reader, output = IO.pipe
    allow(transport).to receive(:send_traces) do |events|
      if Process.pid == parent_pid
        sent << events
        release_send.pop if events == ["in flight"]
      else
        Marshal.dump(events, output)
        output.flush
      end
      []
    end
    writer.write("in flight")
    expect(Timeout.timeout(5) { sent.pop }).to eq(["in flight"])
    writer.write("parent")
    child = Process.fork do
      reader.close
      writer.write("child")
      writer.shutdown!
      output.close
      exit! 0
    end
    output.close
    child_events = Timeout.timeout(5) { Marshal.load(reader) }
    _, status = Timeout.timeout(5) { Process.wait2(child) }
    child = nil
    expect(status.success?).to be(true)
    expect(child_events).to eq(["child"])
    expect(reader.read).to eq("")

    release_send << true
    writer.shutdown!
    expect(Timeout.timeout(5) { sent.pop }).to eq(["parent"])
    expect(sent).to be_empty
  ensure
    release_send << true
    if child
      Process.kill("KILL", child)
      Process.wait(child)
    end
    reader&.close
    output&.close unless output&.closed?
  end

  it "does not accept events after shutdown" do
    writer.shutdown!
    expect(writer.write(trace)).to be(false)
  end
end
