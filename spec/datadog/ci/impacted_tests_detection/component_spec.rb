# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/impacted_tests_detection/component"

RSpec.describe Datadog::CI::ImpactedTestsDetection::Component do
  subject(:component) { described_class.new(enabled: initial_enabled) }

  let(:initial_enabled) { true }
  let(:library_settings) { double("library_settings", impacted_tests_enabled?: impacted_tests_enabled) }
  let(:test_session) { double("test_session", base_commit_sha: base_commit_sha) }
  let(:base_commit_sha) { "abc123" }
  let(:impacted_tests_enabled) { true }
  let(:changed_files_set) { Set.new(["file1.rb:2:5", "file2.rb:4:6"]) }

  let(:git_worker) { spy("git_worker") }

  before do
    # Create a mock git diff output that would result in the changed_files_set
    allow(Datadog::CI::Git::LocalRepository).to receive(:get_changes_since).and_return(
      Datadog::CI::Git::Diff.parse_diff_output(generate_git_diff_output(changed_files_set))
    )
    allow(Datadog.send(:components)).to receive(:git_tree_upload_worker).and_return(git_worker)

    allow(Datadog.logger).to receive(:warn)
  end

  describe "#configure" do
    context "when impacted tests are disabled in library settings" do
      let(:impacted_tests_enabled) { false }

      it "disables the component and returns early" do
        component.configure(library_settings, test_session)
        expect(component.enabled?).to be false
        expect(git_worker).not_to have_received(:wait_until_done)
      end
    end

    context "when base_commit_sha is nil" do
      let(:base_commit_sha) { nil }

      before do
        expect(Datadog::CI::Git::LocalRepository).to receive(:base_commit_sha).and_return(base_commit_sha)
      end

      it "disables the component" do
        component.configure(library_settings, test_session)

        expect(component.enabled?).to be false
        expect(git_worker).to have_received(:wait_until_done)
      end
    end

    context "when get_changes_since returns empty diff" do
      before do
        allow(Datadog::CI::Git::LocalRepository).to receive(:get_changes_since).and_return(
          Datadog::CI::Git::Diff.parse_diff_output(generate_git_diff_output(Set.new))
        )
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
        expect(git_worker).to have_received(:wait_until_done)
      end
    end

    context "when @enabled is already false before configure" do
      let(:initial_enabled) { false }

      it "remains disabled and does not proceed" do
        expect(Datadog::CI::Git::LocalRepository).not_to receive(:get_changes_since)
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

  describe "#modified?" do
    let(:test_span) { instance_double(Datadog::CI::Test, source_file: source_file, start_line: start_line, end_line: end_line) }
    let(:source_file) { "file1.rb" }
    let(:start_line) { 1 }
    let(:end_line) { 10 }

    before do
      component.configure(library_settings, test_session)
    end

    context "when component is not enabled" do
      let(:impacted_tests_enabled) { false }

      it "returns false" do
        expect(component.modified?(test_span)).to be false
      end
    end

    context "when test_span.source_file is nil" do
      let(:source_file) { nil }

      it "returns false" do
        expect(component.modified?(test_span)).to be false
      end
    end

    context "when test_span.source_file is in @changed_files" do
      it "returns true" do
        expect(component.modified?(test_span)).to be true
      end
    end

    context "when test_span.source_file is not in @changed_files" do
      let(:source_file) { "not_in_set.rb" }

      it "returns false" do
        expect(component.modified?(test_span)).to be false
      end
    end
  end

  describe "#tag_modified_test" do
    let(:test_span) { instance_double(Datadog::CI::Test, source_file: source_file) }
    let(:source_file) { "file1.rb" }

    before do
      component.configure(library_settings, test_session)
    end

    context "when test is modified" do
      before do
        allow(component).to receive(:modified?).with(test_span).and_return(true)
      end

      it "sets the is_modified tag" do
        expect(test_span).to receive(:set_tag).with(Datadog::CI::Ext::Test::TAG_TEST_IS_MODIFIED, "true")

        component.tag_modified_test(test_span)
      end
    end

    context "when test is not modified" do
      before do
        allow(component).to receive(:modified?).with(test_span).and_return(false)
      end

      it "does not set the is_modified tag" do
        expect(test_span).not_to receive(:set_tag)

        component.tag_modified_test(test_span)
      end
    end
  end
end
