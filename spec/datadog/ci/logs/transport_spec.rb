# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/logs/transport"

RSpec.describe Datadog::CI::Logs::Transport do
  subject(:transport) do
    described_class.new(
      api: api,
      max_payload_size: max_payload_size
    )
  end

  let(:api) { spy(:api) }
  let(:max_payload_size) { described_class::DEFAULT_MAX_PAYLOAD_SIZE }

  describe "#send_events" do
    subject(:send_events) { transport.send_events(events) }

    context "with nil events" do
      let(:events) { nil }

      it "returns empty array" do
        expect(send_events).to eq([])
      end

      it "does not make any API calls" do
        send_events
        expect(api).not_to have_received(:logs_intake_request)
      end
    end

    context "with empty events" do
      let(:events) { [] }

      it "returns empty array" do
        expect(send_events).to eq([])
      end

      it "does not make any API calls" do
        send_events
        expect(api).not_to have_received(:logs_intake_request)
      end
    end

    context "with single event" do
      let(:events) { [event] }
      let(:event) { {message: "test message"} }

      it "sends event to API" do
        send_events

        expect(api).to have_received(:logs_intake_request).with(
          path: "/v1/input",
          payload: "[#{event.to_json}]"
        )
      end

      it "returns API responses" do
        expect(send_events).to eq([api])
      end
    end

    context "with multiple events" do
      let(:events) { [event1, event2] }
      let(:event1) { {message: "test message 1"} }
      let(:event2) { {message: "test message 2"} }

      it "sends events to API in single payload" do
        send_events

        expect(api).to have_received(:logs_intake_request).with(
          path: "/v1/input",
          payload: "[#{event1.to_json},#{event2.to_json}]"
        )
      end
    end

    context "when event is too large" do
      let(:events) { [large_event] }
      let(:large_event) { {message: "x" * (max_payload_size + 1)} }
      let(:max_payload_size) { 10 }

      it "drops the event" do
        send_events

        expect(api).not_to have_received(:logs_intake_request)
      end
    end

    context "when payload needs chunking" do
      let(:events) { [event1, event2] }
      let(:event1) { {message: "test1"} }
      let(:event2) { {message: "test2"} }
      let(:max_payload_size) { 20 }

      it "sends events in multiple chunks" do
        send_events

        expect(api).to have_received(:logs_intake_request).with(
          path: "/v1/input",
          payload: "[#{event1.to_json}]"
        ).ordered

        expect(api).to have_received(:logs_intake_request).with(
          path: "/v1/input",
          payload: "[#{event2.to_json}]"
        ).ordered
      end

      it "returns API responses for each chunk" do
        expect(send_events).to eq([api, api])
      end
    end
  end
end
