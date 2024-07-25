# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/transport/telemetry"

RSpec.describe Datadog::CI::Transport::Telemetry do
  describe ".events_enqueued_for_serialization" do
    subject { described_class.events_enqueued_for_serialization(count) }

    let(:count) { 1 }

    it "increments the events enqueued metric" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc).with(Datadog::CI::Ext::Telemetry::METRIC_EVENTS_ENQUEUED, count)

      subject
    end
  end

  describe ".endpoint_payload_events_count" do
    subject { described_class.endpoint_payload_events_count(count, endpoint) }

    let(:count) { 1 }
    let(:endpoint) { "test_cycle" }

    it "tracks the endpoint payload events count distribution" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:distribution).with(
        Datadog::CI::Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_EVENTS_COUNT,
        count.to_f,
        {Datadog::CI::Ext::Telemetry::TAG_ENDPOINT => endpoint}
      )

      subject
    end
  end

  describe ".endpoint_payload_serialization_ms" do
    subject { described_class.endpoint_payload_serialization_ms(duration_ms, endpoint) }

    let(:duration_ms) { 1.5 }
    let(:endpoint) { "test_cycle" }

    it "tracks the endpoint payload events serialization duration distribution" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:distribution).with(
        Datadog::CI::Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_EVENTS_SERIALIZATION_MS,
        duration_ms,
        {Datadog::CI::Ext::Telemetry::TAG_ENDPOINT => endpoint}
      )

      subject
    end
  end

  describe ".endpoint_payload_dropped" do
    subject { described_class.endpoint_payload_dropped(count, endpoint) }

    let(:count) { 1 }
    let(:endpoint) { "test_cycle" }

    it "increments the endpoint payload dropped metric" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc).with(
        Datadog::CI::Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_DROPPED,
        count,
        {Datadog::CI::Ext::Telemetry::TAG_ENDPOINT => endpoint}
      )

      subject
    end
  end
end
