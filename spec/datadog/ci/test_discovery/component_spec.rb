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

  describe "#on_test_session_start" do
    let(:output_path) { "/tmp/test_discovery.json" }

    context "when test discovery mode is enabled" do
      let(:enabled) { true }

      before do
        allow(File).to receive(:open).with("/tmp/test_discovery.json", "w").and_return(double("file"))
        allow(FileUtils).to receive(:mkdir_p)
        allow(Dir).to receive(:exist?).with("/tmp").and_return(true)
      end

      it "opens output file for writing" do
        component.on_test_session_start

        expect(File).to have_received(:open).with("/tmp/test_discovery.json", "w")
      end

      context "when output_path is nil" do
        let(:output_path) { nil }

        before do
          allow(File).to receive(:open).with("./.dd/test_discovery/tests.json", "w").and_return(double("file"))
          allow(FileUtils).to receive(:mkdir_p)
          allow(Dir).to receive(:exist?).with("./.dd/test_discovery").and_return(false)
        end

        it "uses default output path" do
          component.on_test_session_start

          expect(FileUtils).to have_received(:mkdir_p).with("./.dd/test_discovery")
          expect(File).to have_received(:open).with("./.dd/test_discovery/tests.json", "w")
        end
      end

      context "when output directory doesn't exist" do
        before do
          allow(Dir).to receive(:exist?).with("/tmp").and_return(false)
        end

        it "creates the output directory" do
          component.on_test_session_start

          expect(FileUtils).to have_received(:mkdir_p).with("/tmp")
        end
      end
    end

    context "when test discovery mode is disabled" do
      let(:enabled) { false }

      before do
        allow(File).to receive(:open)
      end

      it "does not open output file" do
        component.on_test_session_start

        expect(File).not_to have_received(:open)
      end
    end
  end

  describe "#on_test_session_end" do
    let(:test_session) { double("test_session") }
    let(:output_stream) { double("output_stream", close: nil) }

    before do
      component.instance_variable_set(:@output_stream, output_stream)
    end

    context "when test discovery mode is enabled" do
      let(:enabled) { true }

      it "closes the output stream" do
        component.on_test_session_end

        expect(output_stream).to have_received(:close)
        expect(component.instance_variable_get(:@output_stream)).to be_nil
      end
    end

    context "when test discovery mode is disabled" do
      let(:enabled) { false }

      it "does not close the output stream" do
        component.on_test_session_end

        expect(output_stream).not_to have_received(:close)
      end
    end
  end

  describe "#shutdown!" do
    context "when output stream is open" do
      let(:output_stream) { double("output_stream", closed?: false, close: nil) }

      before do
        component.instance_variable_set(:@output_stream, output_stream)
      end

      it "closes the output stream" do
        component.shutdown!

        expect(output_stream).to have_received(:close)
        expect(component.instance_variable_get(:@output_stream)).to be_nil
      end
    end

    context "when output stream is already closed" do
      let(:output_stream) { double("output_stream", closed?: true, close: nil) }

      before do
        component.instance_variable_set(:@output_stream, output_stream)
      end

      it "does not close the output stream" do
        component.shutdown!

        expect(output_stream).not_to have_received(:close)
      end
    end

    context "when output stream is nil" do
      before do
        component.instance_variable_set(:@output_stream, nil)
      end

      it "does not raise an error" do
        expect { component.shutdown! }.not_to raise_error
      end
    end
  end

  describe "#on_test_started" do
    let(:test) { 
      double("test", 
        mark_test_discovery_mode!: nil,
        name: "test_example",
        test_suite_name: "ExampleSuite", 
        source_file: "/path/to/test.rb",
        datadog_test_id: "ExampleSuite.test_example.nil"
      ) 
    }

    context "when test discovery mode is enabled" do
      let(:enabled) { true }

      it "marks the test as being in test discovery mode" do
        component.on_test_started(test)

        expect(test).to have_received(:mark_test_discovery_mode!)
      end

      context "when output stream is available" do
        let(:output_stream) { instance_double(File, puts: nil) }

        before do
          component.instance_variable_set(:@output_stream, output_stream)
        end

        it "writes test information as JSON to output stream" do
          component.on_test_started(test)

          expected_json = JSON.generate({
            "name" => "test_example",
            "suite" => "ExampleSuite",
            "sourceFile" => "/path/to/test.rb",
            "fqn" => "ExampleSuite.test_example.nil"
          })

          expect(output_stream).to have_received(:puts).with(expected_json)
        end
      end

      context "when output stream is not available" do
        before do
          component.instance_variable_set(:@output_stream, nil)
        end

        it "does not write to output stream" do
          expect { component.on_test_started(test) }.not_to raise_error
        end
      end
    end

    context "when test discovery mode is disabled" do
      let(:enabled) { false }

      it "does not mark the test" do
        component.on_test_started(test)

        expect(test).not_to have_received(:mark_test_discovery_mode!)
      end

      it "does not write to output stream" do
        output_stream = instance_double(File, puts: nil)
        component.instance_variable_set(:@output_stream, output_stream)
        
        component.on_test_started(test)

        expect(output_stream).not_to have_received(:puts)
      end
    end
  end
end
