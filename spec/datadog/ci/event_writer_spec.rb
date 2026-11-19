# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "datadog/ci/event_writer"

RSpec.describe Datadog::CI::EventWriter do
  let(:transport) { double(:transport, send_traces: []) }
  let(:logger) { double(:logger, warn: nil) }
  let(:writer) { described_class.new(transport: transport, logger: logger, flush_interval: 60, buffer_size: 2) }
  let(:trace) { double(:trace) }

  before { use_real_tracer! }

  after { writer.shutdown! }

  it "flushes queued events once at shutdown" do
    expect(transport).to receive(:send_traces).with([trace]).once
    expect(writer.write(trace)).to be(true)
    writer.shutdown!
    writer.shutdown!
  end

  it "limits buffered events without raising into the test" do
    2.times { expect(writer.write(trace)).to be(true) }
    expect(logger).to receive(:warn).with(/buffer is full/)
    expect(writer.write(trace)).to be(false)
    expect(transport).to receive(:send_traces).with([trace, trace])
    writer.flush
  end

  it "logs transport errors without raising into the test" do
    allow(transport).to receive(:send_traces).and_raise(IOError, "connection closed")
    expect(logger).to receive(:warn).with(/connection closed/)
    writer.write(trace)
    expect { writer.flush }.not_to raise_error
  end

  it "does not resend the parent buffer from a forked worker" do
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    reader, output = IO.pipe
    allow(transport).to receive(:send_traces) do |events|
      Marshal.dump(events, output)
      output.flush
    end
    writer.write("parent")
    child = Process.fork do
      reader.close
      writer.write("child")
      writer.shutdown!
      output.close
      exit! 0
    end
    child_events = Timeout.timeout(5) { Marshal.load(reader) }
    _, status = Process.wait2(child)
    expect(status.success?).to be(true)
    expect(child_events).to eq(["child"])

    writer.flush
    expect(Timeout.timeout(5) { Marshal.load(reader) }).to eq(["parent"])
  ensure
    reader&.close
    output&.close
  end

  it "does not accept events after shutdown" do
    writer.shutdown!
    expect(writer.write(trace)).to be(false)
  end
end
