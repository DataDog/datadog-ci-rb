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
    subject { described_class.endpoint_payload_events_count(count, endpoint: endpoint) }

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
    subject { described_class.endpoint_payload_serialization_ms(duration_ms, endpoint: endpoint) }

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
    subject { described_class.endpoint_payload_dropped(count, endpoint: endpoint) }

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

  describe ".endpoint_payload_requests" do
    subject { described_class.endpoint_payload_requests(count, endpoint: endpoint, compressed: compressed) }

    let(:count) { 1 }
    let(:endpoint) { "test_cycle" }
    let(:compressed) { true }

    it "increments the endpoint payload requests metric" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc).with(
        Datadog::CI::Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_REQUESTS,
        count,
        {
          Datadog::CI::Ext::Telemetry::TAG_ENDPOINT => endpoint,
          Datadog::CI::Ext::Telemetry::TAG_REQUEST_COMPRESSED => "true"
        }
      )

      subject
    end

    context "when not compressed" do
      let(:compressed) { false }

      it "incremenets metric without request compressed tag" do
        expect(Datadog::CI::Utils::Telemetry).to receive(:inc).with(
          Datadog::CI::Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_REQUESTS,
          count,
          {Datadog::CI::Ext::Telemetry::TAG_ENDPOINT => endpoint}
        )

        subject
      end
    end
  end

  describe ".endpoint_payload_requests_ms" do
    subject { described_class.endpoint_payload_requests_ms(duration_ms, endpoint: endpoint) }

    let(:duration_ms) { 1.5 }
    let(:endpoint) { "test_cycle" }

    it "tracks the endpoint payload requests duration distribution" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:distribution).with(
        Datadog::CI::Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_REQUESTS_MS,
        duration_ms,
        {Datadog::CI::Ext::Telemetry::TAG_ENDPOINT => endpoint}
      )

      subject
    end
  end

  describe ".endpoint_payload_bytes" do
    subject { described_class.endpoint_payload_bytes(bytesize, endpoint: endpoint) }

    let(:bytesize) { 4 }
    let(:endpoint) { "test_cycle" }

    it "tracks the endpoint payload bytes distribution" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:distribution).with(
        Datadog::CI::Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_BYTES,
        bytesize.to_f,
        {Datadog::CI::Ext::Telemetry::TAG_ENDPOINT => endpoint}
      )

      subject
    end
  end

  describe ".endpoint_payload_requests_errors" do
    subject { described_class.endpoint_payload_requests_errors(count, endpoint: endpoint, error_type: error_type, status_code: status_code) }

    let(:count) { 1 }
    let(:endpoint) { "test_cycle" }
    let(:error_type) { "error" }
    let(:status_code) { 500 }

    it "increments the endpoint payload requests errors metric" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc).with(
        Datadog::CI::Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_REQUESTS_ERRORS,
        count,
        {
          Datadog::CI::Ext::Telemetry::TAG_ENDPOINT => endpoint,
          Datadog::CI::Ext::Telemetry::TAG_ERROR_TYPE => error_type,
          Datadog::CI::Ext::Telemetry::TAG_STATUS_CODE => status_code
        }
      )

      subject
    end

    context "when error type and status code are not provided" do
      let(:error_type) { nil }
      let(:status_code) { nil }

      it "increments the endpoint payload requests errors metric without error type and status code tags" do
        expect(Datadog::CI::Utils::Telemetry).to receive(:inc).with(
          Datadog::CI::Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_REQUESTS_ERRORS,
          count,
          {Datadog::CI::Ext::Telemetry::TAG_ENDPOINT => endpoint}
        )

        subject
      end
    end
  end
end
