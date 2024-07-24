# frozen_string_literal: true

RSpec.describe Datadog::CI::Transport::Telemetry do
  describe ".events_enqueued_for_serialization" do
    subject(:events_enqueued_for_serialization) { described_class.events_enqueued_for_serialization(count) }

    let(:count) { 1 }

    it "increments the events enqueued metric" do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc).with(Datadog::CI::Ext::Telemetry::METRIC_EVENTS_ENQUEUED, count)

      events_enqueued_for_serialization
    end
  end
end
