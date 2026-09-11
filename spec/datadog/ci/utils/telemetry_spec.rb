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

  describe ".itr_forced_run" do
    subject(:itr_forced_run) { described_class.itr_forced_run }

    it "records a forced test run" do
      expect(telemetry).to receive(:inc).with(
        Datadog::CI::Ext::Telemetry::NAMESPACE,
        Datadog::CI::Ext::Telemetry::METRIC_ITR_FORCED_RUN,
        1,
        tags: {
          Datadog::CI::Ext::Telemetry::TAG_EVENT_TYPE => Datadog::CI::Ext::Telemetry::EventType::TEST
        }
      )

      itr_forced_run
    end
  end

  describe ".itr_unskippable" do
    subject(:itr_unskippable) { described_class.itr_unskippable }

    it "records an unskippable test" do
      expect(telemetry).to receive(:inc).with(
        Datadog::CI::Ext::Telemetry::NAMESPACE,
        Datadog::CI::Ext::Telemetry::METRIC_ITR_UNSKIPPABLE,
        1,
        tags: {
          Datadog::CI::Ext::Telemetry::TAG_EVENT_TYPE => Datadog::CI::Ext::Telemetry::EventType::TEST
        }
      )

      itr_unskippable
    end
  end

  describe ".record_dynamic_atr_retries" do
    context "with custom buckets" do
      subject(:record) { described_class.record_dynamic_atr_retries(has_custom_buckets: true) }

      it "records the metric with has_custom_buckets tag" do
        expect(telemetry).to receive(:inc).with(
          Datadog::CI::Ext::Telemetry::NAMESPACE,
          Datadog::CI::Ext::Telemetry::METRIC_DYNAMIC_ATR_RETRIES_ENABLED,
          1,
          tags: {Datadog::CI::Ext::Telemetry::TAG_HAS_CUSTOM_BUCKETS => "true"}
        )

        record
      end
    end

    context "without custom buckets" do
      subject(:record) { described_class.record_dynamic_atr_retries(has_custom_buckets: false) }

      it "records the metric with no tags" do
        expect(telemetry).to receive(:inc).with(
          Datadog::CI::Ext::Telemetry::NAMESPACE,
          Datadog::CI::Ext::Telemetry::METRIC_DYNAMIC_ATR_RETRIES_ENABLED,
          1,
          tags: {}
        )

        record
      end
    end
  end
end
