# frozen_string_literal: true

require_relative "../../../spec_helper"

require "datadog/ci/test_discovery/component"

RSpec.describe Datadog::CI::TestDiscovery::Component do
  let(:enabled) { false }
  let(:output_path) { nil }

  subject(:component) do
    described_class.new(
      enabled: enabled,
      output_path: output_path
    )
  end

  describe "#initialize" do
    it "stores the enabled and output_path settings" do
      expect(component.instance_variable_get(:@enabled)).to eq(enabled)
      expect(component.instance_variable_get(:@output_path)).to eq(output_path)
    end
  end

  describe "#configure" do
    let(:library_settings) { double("library_settings") }
    let(:test_session) { double("test_session") }

    it "does not raise an error" do
      expect { component.configure(library_settings, test_session) }.not_to raise_error
    end
  end

  describe "#shutdown!" do
    it "does not raise an error" do
      expect { component.shutdown! }.not_to raise_error
    end
  end

  describe "#disable_features_for_test_discovery!" do
    let(:settings) { double("settings") }
    let(:ci_settings) { double("ci_settings") }
    let(:telemetry) { double("telemetry") }

    before do
      allow(settings).to receive(:ci).and_return(ci_settings)
      allow(ci_settings).to receive(:discard_traces=)
      allow(ci_settings).to receive(:itr_enabled=)
      allow(ci_settings).to receive(:git_metadata_upload_enabled=)
      allow(ci_settings).to receive(:retry_failed_tests_enabled=)
      allow(ci_settings).to receive(:retry_new_tests_enabled=)
      allow(ci_settings).to receive(:test_management_enabled=)
      allow(ci_settings).to receive(:agentless_logs_submission_enabled=)
      allow(ci_settings).to receive(:impacted_tests_detection_enabled=)
      allow(settings).to receive(:telemetry).and_return(telemetry)
      allow(telemetry).to receive(:enabled=)
    end

    context "when test discovery mode is enabled" do
      let(:enabled) { true }

      it "disables all feature flags" do
        component.disable_features_for_test_discovery!(settings)

        expect(telemetry).to have_received(:enabled=).with(false)
        expect(ci_settings).to have_received(:discard_traces=).with(true)
        expect(ci_settings).to have_received(:itr_enabled=).with(false)
        expect(ci_settings).to have_received(:git_metadata_upload_enabled=).with(false)
        expect(ci_settings).to have_received(:retry_failed_tests_enabled=).with(false)
        expect(ci_settings).to have_received(:retry_new_tests_enabled=).with(false)
        expect(ci_settings).to have_received(:test_management_enabled=).with(false)
        expect(ci_settings).to have_received(:agentless_logs_submission_enabled=).with(false)
        expect(ci_settings).to have_received(:impacted_tests_detection_enabled=).with(false)
      end
    end

    context "when test discovery mode is disabled" do
      let(:enabled) { false }

      it "does not modify any settings" do
        component.disable_features_for_test_discovery!(settings)

        expect(telemetry).not_to have_received(:enabled=)
        expect(ci_settings).not_to have_received(:discard_traces=)
        expect(ci_settings).not_to have_received(:itr_enabled=)
        expect(ci_settings).not_to have_received(:git_metadata_upload_enabled=)
        expect(ci_settings).not_to have_received(:retry_failed_tests_enabled=)
        expect(ci_settings).not_to have_received(:retry_new_tests_enabled=)
        expect(ci_settings).not_to have_received(:test_management_enabled=)
        expect(ci_settings).not_to have_received(:agentless_logs_submission_enabled=)
        expect(ci_settings).not_to have_received(:impacted_tests_detection_enabled=)
      end
    end
  end
end
