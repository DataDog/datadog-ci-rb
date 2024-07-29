# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_optimisation/telemetry"

RSpec.describe Datadog::CI::TestOptimisation::Telemetry do
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
end
