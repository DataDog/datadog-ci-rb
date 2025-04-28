# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/impacted_tests_detection/component"

RSpec.describe Datadog::CI::ImpactedTestsDetection::Component do
  subject(:component) { described_class.new(enabled: initial_enabled) }

  let(:initial_enabled) { true }
  let(:library_settings) { double("library_settings", impacted_tests_enabled?: impacted_tests_enabled) }
  let(:test_session) { double("test_session", base_commit_sha: base_commit_sha) }
  let(:base_commit_sha) { "abc123" }
  let(:impacted_tests_enabled) { true }
  let(:changed_files_set) { Set.new(["file1.rb", "file2.rb"]) }

  before do
    allow(Datadog::CI::Git::LocalRepository).to receive(:get_changed_files_from_diff).and_return(changed_files_set)

    allow(Datadog.logger).to receive(:warn)
  end

  describe "#configure" do
    context "when impacted tests are disabled in library settings" do
      let(:impacted_tests_enabled) { false }

      it "disables the component and returns early" do
        component.configure(library_settings, test_session)
        expect(component.enabled?).to be false
      end
    end

    context "when base_commit_sha is nil" do
      let(:base_commit_sha) { nil }

      it "disables the component" do
        component.configure(library_settings, test_session)

        expect(component.enabled?).to be false
      end
    end

    context "when get_changed_files_from_diff returns nil" do
      before do
        allow(Datadog::CI::Git::LocalRepository).to receive(:get_changed_files_from_diff).and_return(nil)
      end

      it "disables the component" do
        component.configure(library_settings, test_session)

        expect(component.enabled?).to be false
      end
    end

    context "when all conditions are met" do
      it "sets changed_files and enables the component" do
        component.configure(library_settings, test_session)
        expect(component.enabled?).to be true
        expect(component.instance_variable_get(:@changed_files)).to eq(changed_files_set)
      end
    end

    context "when @enabled is already false before configure" do
      let(:initial_enabled) { false }

      it "remains disabled and does not proceed" do
        expect(Datadog::CI::Git::LocalRepository).not_to receive(:get_changed_files_from_diff)
        component.configure(library_settings, test_session)
        expect(component.enabled?).to be false
      end
    end
  end

  describe "#enabled?" do
    it "returns the current enabled state" do
      expect(component.enabled?).to eq(initial_enabled)
    end
  end
end
