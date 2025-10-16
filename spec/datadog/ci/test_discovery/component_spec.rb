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

  describe "#configure" do
    let(:library_settings) { double("library_settings") }
    let(:test_session) { double("test_session") }

    it "does not raise an error" do
      expect { component.configure(library_settings, test_session) }.not_to raise_error
    end
  end

  describe "#enabled?" do
    context "when enabled is true" do
      let(:enabled) { true }

      it "returns true" do
        expect(component.enabled?).to be true
      end
    end

    context "when enabled is false" do
      let(:enabled) { false }

      it "returns false" do
        expect(component.enabled?).to be false
      end
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

  describe "#start" do
    let(:output_path) { "/tmp/test_discovery.json" }

    context "when test discovery mode is enabled" do
      let(:enabled) { true }

      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(Dir).to receive(:exist?).with("/tmp").and_return(true)
      end

      it "clears the buffer" do
        component.instance_variable_set(:@buffer, ["old_data"])
        component.start

        expect(component.instance_variable_get(:@buffer)).to eq([])
      end

      context "when output_path is nil" do
        let(:output_path) { nil }

        before do
          allow(FileUtils).to receive(:mkdir_p)
          allow(Dir).to receive(:exist?).with("./#{Datadog::CI::Ext::DDTest::PLAN_FOLDER}/test_discovery").and_return(false)
        end

        it "uses default output path and creates directory" do
          component.start

          expect(FileUtils).to have_received(:mkdir_p).with("./#{Datadog::CI::Ext::DDTest::PLAN_FOLDER}/test_discovery")
          expect(component.instance_variable_get(:@output_path)).to eq("./#{Datadog::CI::Ext::DDTest::PLAN_FOLDER}/test_discovery/tests.json")
        end
      end

      context "when output directory doesn't exist" do
        before do
          allow(Dir).to receive(:exist?).with("/tmp").and_return(false)
        end

        it "creates the output directory" do
          component.start

          expect(FileUtils).to have_received(:mkdir_p).with("/tmp")
        end
      end
    end

    context "when test discovery mode is disabled" do
      let(:enabled) { false }

      it "does not modify the buffer" do
        component.instance_variable_set(:@buffer, ["existing_data"])
        component.start

        expect(component.instance_variable_get(:@buffer)).to eq(["existing_data"])
      end
    end
  end

  describe "#finish" do
    let(:output_path) { "/tmp/test_discovery.json" }

    context "when test discovery mode is enabled" do
      let(:enabled) { true }
      let(:file_double) { double("file", puts: nil) }

      before do
        allow(File).to receive(:open).with("/tmp/test_discovery.json", "a").and_yield(file_double)
        component.instance_variable_set(:@buffer, [{"name" => "test1"}, {"name" => "test2"}])
      end

      it "flushes the buffer to file" do
        component.finish

        expect(File).to have_received(:open).with("/tmp/test_discovery.json", "a")
        expect(file_double).to have_received(:puts).with(['{"name":"test1"}', '{"name":"test2"}'])
        expect(component.instance_variable_get(:@buffer)).to be_empty
      end

      context "when buffer is empty" do
        before do
          component.instance_variable_set(:@buffer, [])
        end

        it "does not open file" do
          component.finish

          expect(File).not_to have_received(:open)
        end
      end
    end

    context "when test discovery mode is disabled" do
      let(:enabled) { false }

      it "does not flush buffer" do
        allow(File).to receive(:open)
        component.finish

        expect(File).not_to have_received(:open)
      end
    end
  end

  describe "#shutdown!" do
    let(:output_path) { "/tmp/test_discovery.json" }
    let(:file_double) { double("file", puts: nil) }

    context "when test discovery mode is enabled" do
      let(:enabled) { true }

      before do
        allow(File).to receive(:open).with("/tmp/test_discovery.json", "a").and_yield(file_double)
      end

      context "when buffer has data" do
        before do
          component.instance_variable_set(:@buffer, [{"name" => "test1"}])
        end

        it "flushes the buffer" do
          component.shutdown!

          expect(File).to have_received(:open).with("/tmp/test_discovery.json", "a")
          expect(file_double).to have_received(:puts).with(['{"name":"test1"}'])
          expect(component.instance_variable_get(:@buffer)).to be_empty
        end
      end

      context "when buffer is empty" do
        before do
          component.instance_variable_set(:@buffer, [])
        end

        it "does not open file" do
          component.shutdown!

          expect(File).not_to have_received(:open)
        end
      end
    end

    context "when test discovery mode is disabled" do
      let(:enabled) { false }

      it "does not flush buffer" do
        allow(File).to receive(:open)
        component.shutdown!

        expect(File).not_to have_received(:open)
      end
    end
  end

  describe "#record_test" do
    let(:test) do
      {
        name: "test_example",
        suite: "ExampleSuite",
        module_name: "ExampleModule",
        parameters: "{a: 1, b: 2}",
        source_file: "/path/to/suite.rb"
      }
    end

    context "when test discovery mode is enabled" do
      let(:enabled) { true }

      it "adds test information to buffer" do
        component.record_test(**test)

        expected_test_info = {
          "name" => "test_example",
          "suite" => "ExampleSuite",
          "module" => "ExampleModule",
          "parameters" => "{a: 1, b: 2}",
          "suiteSourceFile" => "/path/to/suite.rb"
        }

        expect(component.instance_variable_get(:@buffer)).to include(expected_test_info)
      end

      context "when buffer reaches max size" do
        let(:output_path) { "/tmp/test_discovery.json" }
        let(:file_double) { double("file", puts: nil) }

        before do
          allow(File).to receive(:open).with("/tmp/test_discovery.json", "a").and_yield(file_double)
          # Fill buffer to one less than max
          buffer_data = Array.new(Datadog::CI::Ext::TestDiscovery::MAX_BUFFER_SIZE - 1) { {"name" => "existing_test"} }
          component.instance_variable_set(:@buffer, buffer_data)
        end

        it "flushes the buffer when max size is reached" do
          component.record_test(**test)

          expect(File).to have_received(:open).with("/tmp/test_discovery.json", "a")
          expect(component.instance_variable_get(:@buffer)).to be_empty
        end
      end
    end

    context "when test discovery mode is disabled" do
      let(:enabled) { false }

      it "does not add to buffer" do
        initial_buffer = component.instance_variable_get(:@buffer)
        component.record_test(**test)

        expect(component.instance_variable_get(:@buffer)).to eq(initial_buffer)
      end
    end
  end

  describe "thread safety" do
    let(:enabled) { true }
    let(:output_path) { "/tmp/test_discovery.json" }
    let(:file_double) { double("file", puts: nil) }

    before do
      allow(File).to receive(:open).with("/tmp/test_discovery.json", "a").and_yield(file_double)
    end

    it "handles concurrent test additions safely" do
      component.start

      # Create multiple threads adding tests concurrently
      threads = 10.times.map do |i|
        Thread.new do
          10.times do |j|
            component.record_test(
              name: "test_#{i}_#{j}",
              suite: "Suite#{i}",
              module_name: "Module#{i}",
              parameters: "{a: #{i}, b: #{j}}",
              source_file: "/path/test_#{i}_#{j}.rb"
            )
          end
        end
      end

      threads.each(&:join)

      # All 100 tests should be in buffer
      expect(component.instance_variable_get(:@buffer).size).to eq(100)
    end
  end
end
