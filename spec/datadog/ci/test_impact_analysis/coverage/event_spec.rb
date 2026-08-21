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
          custom_impacted_files | suite_impacted_files,
          static_dependencies
        )
      )
    end

    let(:custom_impacted_files) { ["file.js", "file.rb"] }
    let(:suite_impacted_files) { ["suite.js", "file.js"] }
    let(:static_dependencies) { [{"dependency.rb" => true, "file.rb" => true}] }

    it "defers merging impacted files until coverage is read, including after serialization" do
      expect(coverage).to eq("file.rb" => true)
      event.to_msgpack
      expect(coverage).to eq("file.rb" => true)

      expect(event.inspect_coverage).to eq(
        "file.rb" => true,
        "file.js" => true,
        "suite.js" => true,
        "dependency.rb" => true
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

    it "matches legacy MessagePack bytes for native and custom paths" do
      root = Datadog::CI::Git::LocalRepository.root
      absolute_native = File.join(root, "app/models/user.rb")
      binary_file = "frontend/binary-\xFF.js".b
      long_file = "frontend/#{"x" * 300}.js"
      custom_files = [
        "frontend/app.js",
        absolute_native,
        "frontend/app.js",
        "frontend/emoji-❤️.js",
        binary_file,
        long_file
      ] + Array.new(20) { |index| "frontend/generated-#{index}.js" }
      coverage = {absolute_native => true}
      files = Datadog::CI::TestImpactAnalysis::Coverage::Files.new(coverage, custom_files)
      event = described_class.new(
        test_id: test_id,
        test_suite_id: test_suite_id,
        test_session_id: test_session_id,
        files: files
      )
      file_serialization = Datadog::CI::FileSerialization

      expect(file_serialization.pack_files(coverage, custom_files, root)).to be_a(String)

      encode = lambda do
        packer = MessagePack::Packer.new
        event.to_msgpack(packer)
        packer.to_s
      end
      native_bytes = encode.call
      allow(file_serialization).to receive(:pack_files).and_return(nil)

      expect(native_bytes).to eq(encode.call)
    end

    it "matches legacy MessagePack bytes for all-absolute paths" do
      root = Datadog::CI::Git::LocalRepository.root
      absolute_files = Array.new(20) do |index|
        File.join(root, "app/generated/model-#{index}.rb")
      end
      coverage = absolute_files.first(10).to_h { |file| [file, true] }
      custom_files = absolute_files.drop(5) + [absolute_files.fetch(5)]
      files = Datadog::CI::TestImpactAnalysis::Coverage::Files.new(coverage, custom_files)
      event = described_class.new(
        test_id: test_id,
        test_suite_id: test_suite_id,
        test_session_id: test_session_id,
        files: files
      )
      file_serialization = Datadog::CI::FileSerialization

      expect(file_serialization.pack_files(coverage, custom_files, root)).to be_a(String)

      encode = lambda do
        packer = MessagePack::Packer.new
        event.to_msgpack(packer)
        packer.to_s
      end
      native_bytes = encode.call
      allow(file_serialization).to receive(:pack_files).and_return(nil)

      expect(native_bytes).to eq(encode.call)
    end

    it "keeps deduplication stable while the packed output buffer grows" do
      root = Datadog::CI::Git::LocalRepository.root
      absolute_files = Array.new(500) do |index|
        File.join(root, "app/generated/#{"directory/" * 3}model-#{index}.rb")
      end
      coverage = absolute_files.first(300).to_h { |file| [file, true] }
      custom_files = absolute_files.drop(200).map do |file|
        file.delete_prefix("#{root}/")
      end
      custom_files.concat(custom_files.first(50))
      files = Datadog::CI::TestImpactAnalysis::Coverage::Files.new(coverage, custom_files)
      event = described_class.new(
        test_id: test_id,
        test_suite_id: test_suite_id,
        test_session_id: test_session_id,
        files: files
      )
      file_serialization = Datadog::CI::FileSerialization

      encode = lambda do
        packer = MessagePack::Packer.new
        event.to_msgpack(packer)
        packer.to_s
      end
      native_bytes = encode.call
      allow(file_serialization).to receive(:pack_files).and_return(nil)

      expect(native_bytes.bytesize).to be > 4_096
      expect(native_bytes).to eq(encode.call)
    end

    it "matches Ruby String hash-key semantics across compatible encodings" do
      root = Datadog::CI::Git::LocalRepository.root
      ascii_utf8 = "frontend/shared.js"
      ascii_binary = ascii_utf8.b
      non_ascii_utf8 = "frontend/café.js"
      non_ascii_binary = non_ascii_utf8.b
      custom_files = [ascii_utf8, ascii_binary, non_ascii_utf8, non_ascii_binary]
      files = Datadog::CI::TestImpactAnalysis::Coverage::Files.new({}, custom_files)
      event = described_class.new(
        test_id: test_id,
        test_suite_id: test_suite_id,
        test_session_id: test_session_id,
        files: files
      )
      file_serialization = Datadog::CI::FileSerialization

      expect(file_serialization.pack_files({}, custom_files, root)).to be_a(String)
      encode = lambda do
        packer = MessagePack::Packer.new
        event.to_msgpack(packer)
        packer.to_s
      end
      native_bytes = encode.call
      allow(file_serialization).to receive(:pack_files).and_return(nil)

      expect(native_bytes).to eq(encode.call)
    end

    it "packs process-relative custom paths directly when the repository prefix is empty" do
      root = Datadog::CI::Git::LocalRepository.root
      relative_file = "frontend/app.js"
      custom_files = [relative_file]
      coverage = {File.join(root, "app/models/user.rb") => true}
      allow(Datadog::CI::Git::LocalRepository).to receive(:relative_path_prefix).and_return("")

      event = described_class.new(
        test_id: test_id,
        test_suite_id: test_suite_id,
        test_session_id: test_session_id,
        files: Datadog::CI::TestImpactAnalysis::Coverage::Files.new(coverage, custom_files)
      )

      native_bytes = begin
        packer = MessagePack::Packer.new
        event.to_msgpack(packer)
        packer.to_s
      end
      allow(Datadog::CI::FileSerialization).to receive(:pack_files).and_return(nil)
      legacy_bytes = begin
        packer = MessagePack::Packer.new
        event.to_msgpack(packer)
        packer.to_s
      end

      expect(native_bytes).to eq(legacy_bytes)
      expect(event.inspect_coverage).to include(relative_file => true)
    end

    it "prepends one stable repository prefix to process-relative custom paths" do
      local_repository = Datadog::CI::Git::LocalRepository
      root = "/workspace/repository"
      prefix = "components/payments/"
      normalized_file = "#{prefix}frontend/app.js"
      coverage = {File.join(root, normalized_file) => true}
      custom_files = ["frontend/app.js", "./frontend/shared.js"]
      allow(local_repository).to receive(:root).and_return(root)
      allow(local_repository).to receive(:relative_path_prefix).and_return(prefix)

      event = described_class.new(
        test_id: test_id,
        test_suite_id: test_suite_id,
        test_session_id: test_session_id,
        files: Datadog::CI::TestImpactAnalysis::Coverage::Files.new(coverage, custom_files)
      )
      encode = lambda do
        packer = MessagePack::Packer.new
        event.to_msgpack(packer)
        packer.to_s
      end

      native_bytes = encode.call
      allow(Datadog::CI::FileSerialization).to receive(:pack_files).and_return(nil)
      fallback_bytes = encode.call

      expect(native_bytes).to eq(fallback_bytes)
      expect(MessagePack.unpack(native_bytes).fetch("files")).to eq(
        [
          {"filename" => normalized_file},
          {"filename" => "#{prefix}frontend/shared.js"}
        ]
      )
    end

    it "serializes static dependency hashes without merging them into coverage" do
      root = Datadog::CI::Git::LocalRepository.root
      native_file = File.join(root, "app/models/user.rb")
      dependency = File.join(root, "app/models/account.rb")
      shared_dependency = File.join(root, "app/models/shared.rb")
      coverage = {native_file => true}
      static_dependencies = [
        {dependency => true, shared_dependency => true},
        {shared_dependency => true, native_file => true}
      ]
      custom_files = ["frontend/app.js"]
      files = Datadog::CI::TestImpactAnalysis::Coverage::Files.new(
        coverage,
        custom_files,
        static_dependencies
      )
      event = described_class.new(
        test_id: test_id,
        test_suite_id: test_suite_id,
        test_session_id: test_session_id,
        files: files
      )
      file_serialization = Datadog::CI::FileSerialization

      expect(
        file_serialization.pack_files(coverage, custom_files, root, static_dependencies)
      ).to be_a(String)

      encode = lambda do
        packer = MessagePack::Packer.new
        event.to_msgpack(packer)
        packer.to_s
      end
      native_bytes = encode.call
      allow(file_serialization).to receive(:pack_files).and_return(nil)

      expect(native_bytes).to eq(encode.call)
      expect(coverage).to eq(native_file => true)
    end

    it "falls back for ASCII-incompatible filename encodings" do
      root = Datadog::CI::Git::LocalRepository.root
      encoded_file = "frontend/app.js".encode(Encoding::UTF_16BE)

      expect(
        Datadog::CI::FileSerialization.pack_files({}, [encoded_file], root)
      ).to be_nil
    end

    it "falls back for unexpected relative static dependency paths" do
      root = Datadog::CI::Git::LocalRepository.root

      expect(
        Datadog::CI::FileSerialization.pack_files({}, [], root, [{"dependency.rb" => true}])
      ).to be_nil
    end

    it "falls back for filenames containing NUL bytes" do
      root = Datadog::CI::Git::LocalRepository.root
      relative_file = "frontend/app\0.js"
      absolute_file = "#{root}/#{relative_file}"

      [relative_file, absolute_file].each do |file|
        expect(
          Datadog::CI::FileSerialization.pack_files({}, [file], root)
        ).to be_nil
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
