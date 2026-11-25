# frozen_string_literal: true

require "fileutils"
require "msgpack"
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

    before do
      require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
      skip "per-test line coverage is not supported on this Ruby" unless described_class.supported?

      described_class.stop_collector
      stub_const("LineCoverageSpecFiles", Module.new)
    end

    after do
      described_class.stop_collector
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
  end
end
