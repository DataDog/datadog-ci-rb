# frozen_string_literal: true

require "fileutils"
require "msgpack"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/line_coverage"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::LineCoverage do
  describe ".ignored_paths" do
    it "ignores the bundle location when it is a directory" do
      Dir.mktmpdir do |bundle_location|
        expect(described_class.ignored_paths(bundle_location)).to eq([File.join(File.realpath(bundle_location), "")])
      end
    end

    it "ignores nothing more without a bundle location, or when the location does not exist" do
      expect(described_class.ignored_paths(nil)).to eq([])
      expect(described_class.ignored_paths(File.join(Dir.tmpdir, "no-such-bundle-location"))).to eq([])
    end
  end

  describe ".start" do
    # Every spec starts the collector for the repository root: it never runs again for another root.
    let(:root) { File.realpath(Datadog::CI::Git::LocalRepository.root) }
    let(:collector) { Datadog::CI::TestImpactAnalysis::Coverage::LineCollector }

    before do
      require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
      skip "per-test line coverage is not supported on this Ruby" unless described_class.supported?

      described_class.stop_collector
    end

    after do
      described_class.stop_collector
    end

    it "takes over a running collector with the same root and ignored paths" do
      expect(described_class.start(root: root, ignored_paths: [])).to be_a(described_class)
      expect(collector).to receive(:start).with(root, []).and_call_original

      expect(described_class.start(root: root, ignored_paths: [])).to be_a(described_class)
    end

    it "stops a running collector and falls back when the ignored paths differ" do
      described_class.start(root: root, ignored_paths: [])
      expect(Datadog.logger).to receive(:warn).with(/is running with repository root #{Regexp.escape(root)} and ignored paths \[\]/)

      expect(described_class.start(root: root, ignored_paths: [File.join(root, "vendor", "")])).to be_nil
      expect(collector.stop).to be(false)
    end

    it "stops a running collector and falls back when the root differs" do
      described_class.start(root: root, ignored_paths: [])
      expect(Datadog.logger).to receive(:warn).with(/is running with repository root #{Regexp.escape(root)}/)

      expect(described_class.start(root: File.join(root, "spec"), ignored_paths: [])).to be_nil
      expect(collector.stop).to be(false)
    end

    it "restarts a stopped collector for the same root with other ignored paths" do
      described_class.start(root: root, ignored_paths: [File.join(root, "vendor", "")])
      described_class.stop_collector

      expect(described_class.start(root: root, ignored_paths: [])).to be_a(described_class)
      expect(collector.stop).to be(true)
    end

    it "does not restart a stopped collector for another root" do
      described_class.start(root: root, ignored_paths: [])
      described_class.stop_collector
      expect(Datadog.logger).to receive(:warn).with(/first ran with repository root #{Regexp.escape(root)}, not #{Regexp.escape(File.join(root, "spec"))}/)
      expect(collector).not_to receive(:start)

      expect(described_class.start(root: File.join(root, "spec"), ignored_paths: [])).to be_nil
    end
  end

  describe "#finish_test" do
    let(:root) { File.realpath(Datadog::CI::Git::LocalRepository.root) }
    let(:collector) { Datadog::CI::TestImpactAnalysis::Coverage::LineCollector }

    before do
      require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
      skip "per-test line coverage is not supported on this Ruby" unless described_class.supported?

      described_class.stop_collector
      stub_const("LineCoverageSpecFiles", Module.new)
    end

    after do
      described_class.stop_collector
    end

    # Executed lines by file name, for the files in directory.
    def lines_in(directory, packed)
      prefix = File.join(directory.delete_prefix(File.join(root, "")), "")
      lines = {}
      MessagePack::Unpacker.new.feed_each(packed) do |map|
        file = map.fetch("filename")
        next unless file.start_with?(prefix)

        lines[file.delete_prefix(prefix)] = Datadog::CI::TestImpactAnalysis::Coverage::LineFiles.lines(map.fetch("bitmap"))
      end
      lines
    end

    # msgpack takes a longer header for a path of 32 bytes or more and again of 256 or
    # more, and for a bitmap of 256 bytes or more.
    it "packs each file as msgpack-ruby packs its path and its binary bitmap" do
      nested_directories = Array.new(3, "d" * 90)
      Dir.mktmpdir("lc", root) do |directory|
        short_path = File.join(directory, "a.rb")
        long_path = File.join(directory, *nested_directories, "b.rb")
        FileUtils.mkdir_p(File.dirname(long_path))
        File.write(short_path, "def LineCoverageSpecFiles.short\n  1\nend\n")
        File.write(long_path, "def LineCoverageSpecFiles.long\n#{"\n" * 2100}  2\nend\n")

        line_coverage = described_class.start(root: root, ignored_paths: [])
        load short_path
        load long_path
        line_coverage.start_test(1)
        LineCoverageSpecFiles.short
        LineCoverageSpecFiles.long
        count, packed = line_coverage.finish_test(1, [])

        maps = []
        MessagePack::Unpacker.new.feed_each(packed) { |map| maps << map }
        repacked = MessagePack::Packer.new
        maps.each { |map| repacked.write(map) }

        expect(packed).to eq(repacked.to_s)
        expect(count).to eq(maps.size)
        relative_directory = directory.delete_prefix(File.join(root, ""))
        bitmaps = maps.to_h { |map| [map.fetch("filename"), map.fetch("bitmap")] }
        expect(bitmaps.keys).to include(
          File.join(relative_directory, "a.rb"),
          File.join(relative_directory, *nested_directories, "b.rb"),
          "spec/datadog/ci/test_impact_analysis/coverage/line_coverage_spec.rb"
        )
        expect(bitmaps.keys.map(&:bytesize)).to include(be < 32, be >= 256)
        expect(bitmaps.values.map(&:bytesize)).to include(be < 256, be >= 256)
      end
    end

    it "gives a script without code no site and no line" do
      Dir.mktmpdir("lc", root) do |directory|
        empty_path = File.join(directory, "empty.rb")
        code_path = File.join(directory, "code.rb")
        File.write(empty_path, "")
        File.write(code_path, "def LineCoverageSpecFiles.code\n  1\nend\n")

        line_coverage = described_class.start(root: root, ignored_paths: [])
        load code_path
        line_coverage.start_test(1)
        sites = collector.stats.fetch(:sites)
        load empty_path
        Object.new.instance_eval(File.read(empty_path), empty_path, 1)
        expect(collector.stats.fetch(:sites)).to eq(sites)
        LineCoverageSpecFiles.code
        _count, packed = line_coverage.finish_test(1, [])

        lines = lines_in(directory, packed)
        expect(lines).not_to have_key("empty.rb")
        expect(lines.fetch("code.rb")).to include(2)
      end
    end

    # Before Ruby 3.3, a rescue clause compiles to an iseq without events.
    it "counts the line of an empty rescue clause that runs" do
      Dir.mktmpdir("lc", root) do |directory|
        path = File.join(directory, "rescued.rb")
        File.write(path, "def LineCoverageSpecFiles.rescued\n  Integer(\"x\")\nrescue ArgumentError\nend\n")

        line_coverage = described_class.start(root: root, ignored_paths: [])
        load path
        line_coverage.start_test(1)
        LineCoverageSpecFiles.rescued
        _count, packed = line_coverage.finish_test(1, [])

        expect(lines_in(directory, packed).fetch("rescued.rb")).to include(2, 3)
      end
    end

    # From Ruby 3.4, an ensure clause compiles to an iseq with a line but without events.
    it "counts the line of an empty ensure clause that runs" do
      skip "an ensure clause has no line of its own before Ruby 3.4" if RUBY_VERSION < "3.4"

      Dir.mktmpdir("lc", root) do |directory|
        path = File.join(directory, "ensured.rb")
        File.write(path, "def LineCoverageSpecFiles.ensured\n  raise ArgumentError\nensure\nend\n")

        line_coverage = described_class.start(root: root, ignored_paths: [])
        load path
        line_coverage.start_test(1)
        expect { LineCoverageSpecFiles.ensured }.to raise_error(ArgumentError)
        _count, packed = line_coverage.finish_test(1, [])

        expect(lines_in(directory, packed).fetch("ensured.rb")).to include(2, 3)
      end
    end
  end

  # Before Ruby 4, the GC that frees a Ractor turns off the VM's event flags, and with them
  # every line trap.
  describe "after the GC frees a finished Ractor" do
    let(:root) { File.realpath(Datadog::CI::Git::LocalRepository.root) }
    let(:script) { File.join(__dir__, "fixtures", "line_coverage", "ractor_gc.rb") }

    before do
      require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
      skip "per-test line coverage is not supported on this Ruby" unless described_class.supported?

      # So that the child does not load the bootstrap of child processes.
      described_class.stop_collector
    end

    # In a child process, so that this process starts no Ractor.
    it "records the lines of the next test" do
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", File.join(root, "lib"), script, root)

      expect(status).to be_success, stderr
      line = File.readlines(script).index { |source| source.strip == ":after_collection" } + 1
      expect(stdout.split(",").map(&:to_i)).to include(line)
    end
  end
end
