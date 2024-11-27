# frozen_string_literal: true

require "pp"

require_relative "../../../../../lib/datadog/ci/test_optimisation/coverage/event"

RSpec.describe Datadog::CI::TestOptimisation::Coverage::Event do
  subject do
    described_class.new(
      test_id: test_id,
      test_suite_id: test_suite_id,
      test_session_id: test_session_id,
      coverage: coverage
    )
  end
  let(:test_id) { "1" }
  let(:test_suite_id) { "2" }
  let(:test_session_id) { "3" }
  let(:coverage) { {"file.rb" => true} }

  describe "#valid?" do
    it { is_expected.to be_valid }

    context "when test_id is nil" do
      let(:test_id) { nil }
      before do
        expect(Datadog.logger).to receive(:warn).with(/citestcov event is invalid: \[test_id\] is nil. Event: .*/)
      end

      it { is_expected.not_to be_valid }
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

    context "when coverage is nil" do
      let(:coverage) { nil }
      before do
        expect(Datadog.logger).to receive(:warn).with(/citestcov event is invalid: \[coverage\] is nil. Event: .*/)
      end

      it { is_expected.not_to be_valid }
    end
  end

  describe "#to_msgpack" do
    include_context "msgpack serializer" do
      subject do
        described_class.new(
          test_id: test_id,
          test_suite_id: test_suite_id,
          test_session_id: test_session_id,
          coverage: coverage
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
              {"filename" => "spec/datadog/ci/test_optimisation/coverage/project/file.rb"}
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
  end

  describe "#pretty_inspect" do
    it "returns a human readable version of the event" do
      expect(subject.pretty_inspect).to eq(" Test ID: 1\n" \
       "Test Suite ID: 2\n" \
       "Test Session ID: 3\n" \
       "Files: [file.rb]\n\n")
    end
  end
end
