# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_impact_analysis/telemetry"

RSpec.describe Datadog::CI::TestImpactAnalysis::Telemetry do
  describe ".code_coverage_started" do
    subject(:code_coverage_started) { described_class.code_coverage_started(test) }

    before do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc)
        .with(Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_STARTED, 1, expected_tags)
    end

    let(:test) do
      Datadog::Tracing::SpanOperation.new(
        "test",
        type: Datadog::CI::Ext::AppTypes::TYPE_TEST,
        tags: {
          Datadog::CI::Ext::Test::TAG_FRAMEWORK => "rspec"
        }
      )
    end

    let(:expected_tags) do
      {
        Datadog::CI::Ext::Telemetry::TAG_TEST_FRAMEWORK => "rspec",
        Datadog::CI::Ext::Telemetry::TAG_LIBRARY => Datadog::CI::Ext::Telemetry::Library::CUSTOM
      }
    end

    it { code_coverage_started }
  end

  describe ".code_coverage_finished" do
    subject(:code_coverage_finished) { described_class.code_coverage_finished(test) }

    before do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc)
        .with(Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_FINISHED, 1, expected_tags)
    end

    let(:test) do
      Datadog::Tracing::SpanOperation.new(
        "test",
        type: Datadog::CI::Ext::AppTypes::TYPE_TEST,
        tags: {
          Datadog::CI::Ext::Test::TAG_FRAMEWORK => "rspec"
        }
      )
    end

    let(:expected_tags) do
      {
        Datadog::CI::Ext::Telemetry::TAG_TEST_FRAMEWORK => "rspec",
        Datadog::CI::Ext::Telemetry::TAG_LIBRARY => Datadog::CI::Ext::Telemetry::Library::CUSTOM
      }
    end

    it { code_coverage_finished }
  end

  describe ".code_coverage_is_empty" do
    subject(:code_coverage_is_empty) { described_class.code_coverage_is_empty }

    before do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc)
        .with(Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_IS_EMPTY, 1)
    end

    it { code_coverage_is_empty }
  end

  describe ".code_coverage_files" do
    subject(:code_coverage_files) { described_class.code_coverage_files(count) }

    let(:count) { 42 }

    before do
      expect(Datadog::CI::Utils::Telemetry).to receive(:distribution)
        .with(Datadog::CI::Ext::Telemetry::METRIC_CODE_COVERAGE_FILES, count.to_f)
    end

    it { code_coverage_files }
  end

  describe ".itr_skipped" do
    subject(:itr_skipped) { described_class.itr_skipped }

    before do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc)
        .with(Datadog::CI::Ext::Telemetry::METRIC_ITR_SKIPPED, 1, expected_tags)
    end

    let(:expected_tags) do
      {
        Datadog::CI::Ext::Telemetry::TAG_EVENT_TYPE => Datadog::CI::Ext::Telemetry::EventType::TEST
      }
    end

    it { itr_skipped }
  end

  describe ".itr_forced_run" do
    subject(:itr_forced_run) { described_class.itr_forced_run }

    before do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc)
        .with(Datadog::CI::Ext::Telemetry::METRIC_ITR_FORCED_RUN, 1, expected_tags)
    end

    let(:expected_tags) do
      {
        Datadog::CI::Ext::Telemetry::TAG_EVENT_TYPE => Datadog::CI::Ext::Telemetry::EventType::TEST
      }
    end

    it { itr_forced_run }
  end

  describe ".itr_unskippable" do
    subject(:itr_unskippable) { described_class.itr_unskippable }

    before do
      expect(Datadog::CI::Utils::Telemetry).to receive(:inc)
        .with(Datadog::CI::Ext::Telemetry::METRIC_ITR_UNSKIPPABLE, 1, expected_tags)
    end

    let(:expected_tags) do
      {
        Datadog::CI::Ext::Telemetry::TAG_EVENT_TYPE => Datadog::CI::Ext::Telemetry::EventType::TEST
      }
    end

    it { itr_unskippable }
  end
end
