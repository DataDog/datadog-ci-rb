# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/async_writer"

RSpec.describe Datadog::CI::AsyncWriter do
  subject(:writer) { described_class.new(transport: transport, options: options) }

  let(:options) { {interval: 60.0} }
  let(:transport) { double("transport", send_events: []) }

  before { use_real_tracer! }
  after { writer.stop }

  it "sends queued events at shutdown exactly once" do
    expect(transport).to receive(:send_events).with(["one", "two"]).once
    expect(writer.write("one")).to be(true)
    expect(writer.write("two")).to be(true)
    writer.stop
    writer.stop
    expect(writer).not_to be_running
  end

  it "starts the worker when the first event arrives" do
    expect(writer).not_to be_started
    writer.write("event")
    expect(writer).to be_started
    expect(writer).to be_running
    expect(writer).to be_async
  end

  it "flushes events without stopping the writer" do
    expect(transport).to receive(:send_events).with(["event"]).once
    writer.write("event")
    writer.flush
    expect(writer).to be_running
  end

  it "rejects events after shutdown" do
    writer.stop
    expect(writer.write("event")).to be(false)
    expect(transport).not_to receive(:send_events)
  end

  it "sends events directly when asked to perform" do
    expect(transport).to receive(:send_events).with(["one", "two"])
    expect(writer.perform("one", "two")).to be_nil
  end

  it "logs transport errors without raising into customer code" do
    allow(transport).to receive(:send_events).and_raise(IOError, "connection closed")
    expect(Datadog::CI.logger).to receive(:warn).with(/connection closed/).twice
    expect { writer.perform("direct") }.not_to raise_error
    writer.write("buffered")
    expect { writer.flush }.not_to raise_error
  end

  context "with a short flush interval" do
    let(:options) { {interval: 0.01} }

    it "delivers events without an explicit flush" do
      sent = Queue.new
      allow(transport).to receive(:send_events) { |events| sent << events }
      writer.write("event")
      expect(try_wait_until { !sent.empty? }).to be(true)
      expect(sent.pop).to eq(["event"])
    end
  end

  context "with a small buffer" do
    let(:options) { {buffer_size: 1, interval: 60.0} }

    it "drops excess events and keeps the accepted event" do
      expect(Datadog::CI.logger).to receive(:warn).with(/buffer is full/)
      expect(writer.write("accepted")).to be(true)
      expect(writer.write("excess")).to be(false)
      expect(transport).to receive(:send_events).with(["accepted"])
      writer.flush
    end
  end

  it "delivers child events after a fork without resending parent events" do
    skip "Fork is unavailable" unless Process.respond_to?(:fork)

    writer.write("parent")
    expect_in_fork do
      expect(transport).to receive(:send_events).with(["child"]).once
      writer.write("child")
      writer.stop
    end
    expect(transport).to receive(:send_events).with(["parent"]).once
    writer.stop
  end
end
