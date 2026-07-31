# frozen_string_literal: true

require "pp"

require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/event"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::Event do
  subject do
    described_class.new(
      test_id: test_id,
      test_suite_id: test_suite_id,
      test_session_id: test_session_id,
      files: files
    )
  end
  let(:test_id) { "1" }
  let(:test_suite_id) { "2" }
  let(:test_session_id) { "3" }
  let(:coverage) { {"file.rb" => true} }
  let(:files) { Datadog::CI::TestImpactAnalysis::Coverage::Files.new(coverage) }

  describe "#valid?" do
    it { is_expected.to be_valid }

    context "when test_id is nil" do
      let(:test_id) { nil }

      it { is_expected.to be_valid }
    end

    context "when test_suite_id is nil" do
      let(:test_suite_id) { nil }
      before do
        expect(Datadog.logger).to receive(:warn).with(/citestcov event is invalid: \[test_suite_id\] is nil. Event: .*/)
      end

      it { is_expected.not_to be_valid }
    end

    context "when test_session_id is nil" do
      let(:test_session_id) { nil }
      before do
        expect(Datadog.logger).to receive(:warn).with(/citestcov event is invalid: \[test_session_id\] is nil. Event: .*/)
      end

      it { is_expected.not_to be_valid }
    end

    context "when files are nil" do
      let(:files) { nil }
      before do
        expect(Datadog.logger).to receive(:warn).with(/citestcov event is invalid: \[files\] is nil. Event: .*/)
      end

      it { is_expected.not_to be_valid }
    end
  end

  describe "#inspect_coverage" do
    subject(:event) do
      described_class.new(
        test_id: test_id,
        test_suite_id: test_suite_id,
        test_session_id: test_session_id,
        files: Datadog::CI::TestImpactAnalysis::Coverage::Files.new(
          coverage,
          custom_impacted_files | suite_impacted_files
        )
      )
    end

    let(:custom_impacted_files) { ["file.js", "file.rb"] }
    let(:suite_impacted_files) { ["suite.js", "file.js"] }

    it "defers merging impacted files until coverage is read, including after serialization" do
      expect(coverage).to eq("file.rb" => true)
      event.to_msgpack
      expect(coverage).to eq("file.rb" => true)

      expect(event.inspect_coverage).to eq(
        "file.rb" => true,
        "file.js" => true,
        "suite.js" => true
      )
    end
  end

  describe "#to_msgpack" do
    include_context "msgpack serializer" do
      subject do
        described_class.new(
          test_id: test_id,
          test_suite_id: test_suite_id,
          test_session_id: test_session_id,
          files: files
        )
      end
    end

    it "returns a msgpack representation of the event" do
      expect(msgpack_json).to eq(
        {
          "test_session_id" => 3,
          "test_suite_id" => 2,
          "span_id" => 1,
          "files" => [
            {"filename" => "file.rb"}
          ]
        }
      )
    end

    context "when file paths are absolute" do
      let(:coverage) do
        {
          absolute_path("project/file.rb") => true
        }
      end

      it "converts all file paths to relative to the git root" do
        expect(msgpack_json).to eq(
          {
            "test_session_id" => 3,
            "test_suite_id" => 2,
            "span_id" => 1,
            "files" => [
              {"filename" => "spec/datadog/ci/test_impact_analysis/coverage/project/file.rb"}
            ]
          }
        )
      end
    end

    context "when file paths are relative" do
      let(:current_folder) { File.basename(Dir.pwd) }

      before do
        if Datadog::CI::Git::LocalRepository.instance_variable_defined?(:@prefix_to_root)
          Datadog::CI::Git::LocalRepository.remove_instance_variable(:@prefix_to_root)
        end

        # new_root is one level up from the current folder
        new_root = File.dirname(Dir.pwd)
        allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(new_root)
      end

      after do
        Datadog::CI::Git::LocalRepository.remove_instance_variable(:@prefix_to_root)
      end

      let(:coverage) do
        {
          "project/file.rb" => true,
          "project/file2.rb" => true
        }
      end

      it "converts all file paths to relative to the git root" do
        expect(msgpack_json).to eq(
          {
            "test_session_id" => 3,
            "test_suite_id" => 2,
            "span_id" => 1,
            "files" => [
              {"filename" => "#{current_folder}/project/file.rb"},
              {"filename" => "#{current_folder}/project/file2.rb"}
            ]
          }
        )
      end
    end

    context "when test_id is nil" do
      let(:test_id) { nil }

      it "returns a suite-level msgpack representation of the event" do
        expect(msgpack_json).to eq(
          {
            "test_session_id" => 3,
            "test_suite_id" => 2,
            "files" => [
              {"filename" => "file.rb"}
            ]
          }
        )
      end
    end

    context "coverage in lines format" do
      let(:coverage) { {"file.rb" => {1 => true, 2 => true, 3 => true}} }

      it "returns a msgpack representation of the event without lines information" do
        expect(msgpack_json).to eq(
          {
            "test_session_id" => 3,
            "test_suite_id" => 2,
            "span_id" => 1,
            "files" => [
              {"filename" => "file.rb"}
            ]
          }
        )
      end
    end

    context "multiple files" do
      let(:coverage) { {"file.rb" => true, "file2.rb" => true} }

      it "returns a msgpack representation of the event" do
        expect(msgpack_json).to eq(
          {
            "test_session_id" => 3,
            "test_suite_id" => 2,
            "span_id" => 1,
            "files" => [
              {"filename" => "file.rb"},
              {"filename" => "file2.rb"}
            ]
          }
        )
      end
    end

    context "with impacted files" do
      subject do
        described_class.new(
          test_id: test_id,
          test_suite_id: test_suite_id,
          test_session_id: test_session_id,
          files: Datadog::CI::TestImpactAnalysis::Coverage::Files.new(
            coverage,
            ["file.js", "file.rb"]
          )
        )
      end

      it "includes impacted files without duplicating existing coverage" do
        expect(msgpack_json).to eq(
          {
            "test_session_id" => 3,
            "test_suite_id" => 2,
            "span_id" => 1,
            "files" => [
              {"filename" => "file.rb"},
              {"filename" => "file.js"}
            ]
          }
        )
      end
    end

    context "with test and suite impacted files" do
      subject do
        described_class.new(
          test_id: test_id,
          test_suite_id: test_suite_id,
          test_session_id: test_session_id,
          files: Datadog::CI::TestImpactAnalysis::Coverage::Files.new(
            coverage,
            ["test.js", "shared.js", "suite.js", "shared.js", "file.rb"]
          )
        )
      end

      it "deduplicates files across native, test, and suite coverage" do
        expect(msgpack_json.fetch("files")).to contain_exactly(
          {"filename" => "file.rb"},
          {"filename" => "test.js"},
          {"filename" => "shared.js"},
          {"filename" => "suite.js"}
        )
      end
    end

    context "when native and impacted paths normalize to the same file" do
      let(:repository_relative_file) { "app/models/user.rb" }
      let(:absolute_file) do
        File.join(Datadog::CI::Git::LocalRepository.root, repository_relative_file)
      end

      subject do
        described_class.new(
          test_id: test_id,
          test_suite_id: test_suite_id,
          test_session_id: test_session_id,
          files: Datadog::CI::TestImpactAnalysis::Coverage::Files.new(
            {absolute_file => true},
            [repository_relative_file, absolute_file]
          )
        )
      end

      it "normalizes and emits the repository-relative path once" do
        expect(msgpack_json.fetch("files")).to eq(
          [{"filename" => repository_relative_file}]
        )
      end

      it "also deduplicates relative native coverage against an absolute impacted path" do
        event = described_class.new(
          test_id: test_id,
          test_suite_id: test_suite_id,
          test_session_id: test_session_id,
          files: Datadog::CI::TestImpactAnalysis::Coverage::Files.new(
            {repository_relative_file => true},
            [absolute_file]
          )
        )

        payload = MessagePack.unpack(MessagePack.pack(event))
        expect(payload.fetch("files")).to eq(
          [{"filename" => repository_relative_file}]
        )
      end
    end

    context "when custom paths resolve outside the repository" do
      let(:repository_root) { "/workspace/project" }

      before do
        allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(repository_root)
      end

      let(:coverage) { {File.join(repository_root, "native.rb") => true} }
      let(:files) do
        Datadog::CI::TestImpactAnalysis::Coverage::Files.new(
          coverage,
          [
            File.join(repository_root, "app/frontend/page.js"),
            "/workspace/another-project/page.js",
            repository_root
          ]
        )
      end

      it "omits paths that cannot identify a file in the repository" do
        expect(msgpack_json.fetch("files")).to contain_exactly(
          {"filename" => "native.rb"},
          {"filename" => "app/frontend/page.js"}
        )
      end
    end
  end

  describe "#pretty_inspect" do
    it "returns a human readable version of the event" do
      expect(subject.pretty_inspect).to eq(" Test ID: 1\n" \
       "Test Suite ID: 2\n" \
       "Test Session ID: 3\n" \
       "Files: [file.rb]\n\n")
    end

    context "with absolute paths inside and outside the repository" do
      let(:repository_root) { "/workspace/project" }
      let(:coverage) { {File.join(repository_root, "native.rb") => true} }
      let(:files) do
        Datadog::CI::TestImpactAnalysis::Coverage::Files.new(
          coverage,
          [File.join(repository_root, "frontend/app.js"), "/workspace/outside.js"]
        )
      end

      before do
        allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(repository_root)
      end

      it "shows the normalized files that will be serialized" do
        output = subject.pretty_inspect

        expect(output).to include("native.rb", "frontend/app.js")
        expect(output).not_to include(repository_root, "/workspace/outside.js")
      end
    end
  end
end
