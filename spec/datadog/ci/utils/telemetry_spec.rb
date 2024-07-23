# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/utils/telemetry"

RSpec.describe Datadog::CI::Utils::Telemetry do
  let(:telemetry) { double(:telemetry) }

  before { allow(Datadog).to receive_message_chain(:components, :telemetry).and_return(telemetry) }

  describe ".inc" do
    subject(:inc) { described_class.inc(metric_name, count, tags) }

    let(:metric_name) { "metric_name" }
    let(:count) { 1 }
    let(:tags) { {tag_name: "tag_value"} }

    it "calls telemetry.inc with the expected arguments" do
      expect(telemetry).to receive(:inc)
        .with(Datadog::CI::Ext::Telemetry::NAMESPACE, metric_name, count, tags: tags)

      inc
    end
  end

  describe ".distribution" do
    subject(:distribution) { described_class.distribution(metric_name, value, tags) }

    let(:metric_name) { "metric_name" }
    let(:value) { 1 }
    let(:tags) { {tag_name: "tag_value"} }

    it "calls telemetry.distribution with the expected arguments" do
      expect(telemetry).to receive(:distribution)
        .with(Datadog::CI::Ext::Telemetry::NAMESPACE, metric_name, value, tags: tags)

      distribution
    end
  end
end
