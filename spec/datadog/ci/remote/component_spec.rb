# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/remote/component"

RSpec.describe Datadog::CI::Remote::Component do
  subject(:component) { described_class.new(library_settings_client: library_settings_client) }

  let(:library_settings_client) { instance_double(Datadog::CI::Remote::LibrarySettingsClient) }
  let(:git_tree_upload_worker) { instance_double(Datadog::CI::Worker) }
  let(:test_optimisation) { instance_double(Datadog::CI::TestOptimisation::Component) }
  let(:test_retries) { instance_double(Datadog::CI::TestRetries::Component) }
  let(:test_visibility) { instance_double(Datadog::CI::TestVisibility::Component) }
  let(:test_management) { instance_double(Datadog::CI::TestManagement::Component) }
  let(:impacted_tests_detection) { instance_double(Datadog::CI::ImpactedTestsDetection::Component) }

  let(:configurable_components) do
    [
      test_optimisation,
      test_retries,
      test_visibility,
      test_management,
      impacted_tests_detection
    ]
  end

  before do
    allow(Datadog.send(:components)).to receive(:git_tree_upload_worker).and_return(git_tree_upload_worker)
    allow(Datadog.send(:components)).to receive(:test_optimisation).and_return(test_optimisation)
    allow(Datadog.send(:components)).to receive(:test_retries).and_return(test_retries)
    allow(Datadog.send(:components)).to receive(:test_visibility).and_return(test_visibility)
    allow(Datadog.send(:components)).to receive(:test_management).and_return(test_management)
    allow(Datadog.send(:components)).to receive(:impacted_tests_detection).and_return(impacted_tests_detection)
  end

  describe "#configure" do
    subject { component.configure(test_session) }

    let(:test_session) { instance_double(Datadog::CI::TestSession, distributed: false) }
    let(:library_configuration) do
      instance_double(Datadog::CI::Remote::LibrarySettings, require_git?: require_git)
    end

    context "git upload is not required" do
      let(:require_git) { false }

      before do
        # Mock load_component_state to return false so we fetch configuration
        allow(component).to receive(:load_component_state).and_return(false)

        expect(library_settings_client).to receive(:fetch)
          .with(test_session).and_return(library_configuration).once

        configurable_components.each do |component|
          expect(component).to receive(:configure).with(library_configuration, test_session)
        end
      end

      it { subject }

      it "does not store component state when test session is not distributed" do
        expect(component).not_to receive(:store_component_state)
        subject
      end
    end

    context "git upload is required" do
      let(:require_git) { true }

      before do
        # Mock load_component_state to return false so we fetch configuration
        allow(component).to receive(:load_component_state).and_return(false)

        expect(library_settings_client).to receive(:fetch)
          .with(test_session).and_return(library_configuration).once

        expect(git_tree_upload_worker).to receive(:wait_until_done)
        expect(library_settings_client).to receive(:fetch)
          .with(test_session).and_return(library_configuration)

        configurable_components.each do |component|
          expect(component).to receive(:configure).with(library_configuration, test_session)
        end
      end

      it { subject }

      it "does not store component state when test session is not distributed" do
        expect(component).not_to receive(:store_component_state)
        subject
      end
    end

    context "with distributed test session" do
      let(:test_session) { instance_double(Datadog::CI::TestSession, distributed: true) }
      let(:require_git) { false }

      context "verifying store_component_state is called" do
        before do
          allow(component).to receive(:load_component_state).and_return(false)

          allow(library_settings_client).to receive(:fetch)
            .with(test_session).and_return(library_configuration)

          configurable_components.each do |component|
            allow(component).to receive(:configure).with(library_configuration, test_session)
          end
        end

        it "stores component state when test session is distributed" do
          expect(component).to receive(:store_component_state)
          subject
        end
      end
    end

    context "when component state is loaded" do
      let(:require_git) { false }
      let(:stored_state) { {library_configuration: library_configuration} }

      before do
        # Mock load_component_state and FileStorage.retrieve to simulate loading from file
        allow(Datadog::CI::Utils::FileStorage).to receive(:retrieve)
          .with(Datadog::CI::Remote::Component::FILE_STORAGE_KEY)
          .and_return(stored_state)

        # When load_component_state is called, it will use the mocked FileStorage.retrieve
        # and actually restore the state properly
        allow(component).to receive(:load_component_state).and_call_original

        # Need to mock test_visibility.client_process? which is called in load_component_state
        allow(test_visibility).to receive(:client_process?).and_return(true)

        # Should not fetch configuration
        expect(library_settings_client).not_to receive(:fetch)

        configurable_components.each do |component|
          expect(component).to receive(:configure).with(library_configuration, test_session)
        end

        # Mock store_component_state for verification
        allow(component).to receive(:store_component_state)
      end

      it { subject }

      it "does not store component state when state is loaded from storage" do
        expect(component).not_to receive(:store_component_state)
        subject
      end
    end

    context "when test discovery mode is enabled" do
      subject(:component) do
        described_class.new(
          library_settings_client: library_settings_client,
          test_discovery_mode_enabled: true
        )
      end

      before do
        configurable_components.each do |component|
          expect(component).to receive(:configure).with(instance_of(Datadog::CI::Remote::LibrarySettings), test_session)
        end
      end

      it "skips backend fetching and uses default settings" do
        expect(library_settings_client).not_to receive(:fetch)
        expect(component).not_to receive(:load_component_state)
        expect(component).not_to receive(:store_component_state)

        component.configure(test_session)
      end

      it "creates library configuration with default settings" do
        component.configure(test_session)

        # Verify that the configuration has default settings (all features disabled)
        library_config = component.instance_variable_get(:@library_configuration)
        expect(library_config).to be_instance_of(Datadog::CI::Remote::LibrarySettings)
        expect(library_config.itr_enabled?).to be false
        expect(library_config.code_coverage_enabled?).to be false
        expect(library_config.tests_skipping_enabled?).to be false
        expect(library_config.flaky_test_retries_enabled?).to be false
        expect(library_config.early_flake_detection_enabled?).to be false
        expect(library_config.known_tests_enabled?).to be false
        expect(library_config.test_management_enabled?).to be false
        expect(library_config.impacted_tests_enabled?).to be false
      end
    end
  end
end
