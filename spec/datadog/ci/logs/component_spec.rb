# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/logs/component"

RSpec.describe Datadog::CI::Logs::Component do
  let(:component) { described_class.new(enabled: enabled, transport: transport) }

  let(:enabled) { true }
  let(:transport) { instance_double(Datadog::CI::Logs::Transport, send_events: true) }

  describe "#write" do
    subject(:write) { component.write(event) }
    let(:event) { {name: "test_event", value: "test_value"} }

    context "when component is enabled" do
      let(:enabled) { true }

      it "returns the event" do
        expect(write).to eq(event)
      end
    end

    context "when component is disabled" do
      let(:enabled) { false }

      it "returns nil" do
        expect(write).to be_nil
      end
    end
  end
end
