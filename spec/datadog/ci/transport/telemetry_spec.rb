# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/transport/telemetry"

RSpec.describe Datadog::CI::Transport::Telemetry do
  describe ".events_enqueued_for_serialization" do
    subject(:events_enqueued_for_serialization) { described_class.events_enqueued_for_serialization(count) }

    let(:count) { 1 }

    it "increments the events enqueued metric" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc).with(Datadog::CI::Ext::Telemetry::METRIC_EVENTS_ENQUEUED, count)

      events_enqueued_for_serialization
    end
  end

  describe ".endpoint_payload_events_count" do
    subject(:endpoint_payload_events_count) { described_class.endpoint_payload_events_count(count, endpoint) }

    let(:count) { 1 }
    let(:endpoint) { "citestcycle" }

    it "tracks the endpoint payload events count distribution" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:distribution).with(
        Datadog::CI::Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_EVENTS_COUNT,
        count.to_f,
        {Datadog::CI::Ext::Telemetry::TAG_ENDPOINT => endpoint}
      )

      endpoint_payload_events_count
    end
  end
end
