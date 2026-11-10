# frozen_string_literal: true

require "tmpdir"
require "pathname"
require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/file_access"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::FileAccess do
  let(:root) { File.realpath(Dir.mktmpdir) }
  let(:fixture) { File.join(root, "fixture.json") }
  let(:other_fixture) { File.join(root, "template.html") }
  let(:mode) { :multi }
  subject(:collector) { described_class.new(root: root, ignored_path: File.join(root, "vendor"), threading_mode: mode) }

  before do
    File.write(fixture, "{\"value\":42}\n")
    File.write(other_fixture, "<p>fixture</p>\n")
  end

  after do
    collector.stop
    FileUtils.remove_entry(root)
  end

  {
    "File.open" => ->(path) { File.open(path, "r") { |file| file.read(100) } },
    "File.new" => ->(path) {
      file = File.new(path)
      result = file.read
      file.close
      result
    },
    "Kernel.open" => ->(path) { Kernel.open(path) { |file| file.read } },
    "File.read" => ->(path) { File.read(path, encoding: "UTF-8") },
    "IO.read" => ->(path) { IO.read(path) },
    "File.binread" => ->(path) { File.binread(path) },
    "IO.binread" => ->(path) { IO.binread(path) },
    "File.readlines" => ->(path) { File.readlines(path).join },
    "IO.readlines" => ->(path) { IO.readlines(path).join },
    "File.foreach" => ->(path) {
      lines = []
      File.foreach(path) { |line| lines << line }
      lines.join
    },
    "IO.foreach" => ->(path) { IO.foreach(path).to_a.join },
    "File.sysopen" => ->(path) { IO.open(File.sysopen(path)) { |io| io.read } },
    "Pathname#read" => ->(path) { Pathname.new(path).read }
  }.each do |name, read|
    it "records #{name} and preserves its result" do
      collector.start
      result = read.call(fixture)
      expect(collector.stop).to eq(fixture => true)
      expect(result).to eq("{\"value\":42}\n")
    end
  end

  it "records a file before the open block raises and preserves the exception" do
    collector.start
    expect { File.open(fixture) { raise "customer error" } }.to raise_error("customer error")
    expect(collector.stop).to eq(fixture => true)
  end

  it "preserves errors from file operations" do
    collector.start
    expect { File.read(File.join(root, "missing")) }.to raise_error(Errno::ENOENT)
    expect { File.open(File.join(root, "missing")) }.to raise_error(Errno::ENOENT)
  end

  it "does not coerce a path-like object twice" do
    path = double("path")
    expect(path).to receive(:to_path).once.and_return(fixture)
    collector.start
    File.read(path)
    expect(collector.stop).to eq(fixture => true)
  end

  it "collects lazy foreach only when it is consumed" do
    collector.start
    enumerator = File.foreach(fixture, chomp: true)
    expect(collector.stop).to be_empty
    collector.start
    expect(enumerator.to_a).to eq(['{"value":42}'])
    expect(collector.stop).to eq(fixture => true)
  end

  it "normalizes relative paths at access time and deduplicates" do
    collector.start
    Dir.chdir(root) { File.read("./fixture.json") }
    File.read(fixture)
    expect(collector.stop).to eq(fixture => true)
  end

  it "does not expand literal tildes" do
    FileUtils.mkdir_p(File.join(root, "~"))
    path = File.join(root, "~", "fixture")
    File.write(path, "fixture")
    collector.start
    Dir.chdir(root) { File.read("~/fixture") }
    expect(collector.stop).to eq(path => true)
  end

  it "records symlink names and targets" do
    link = File.join(root, "link.json")
    File.symlink(fixture, link)
    collector.start
    File.read(link)
    expect(collector.stop).to eq(link => true, fixture => true)
  end

  it "resolves symlinks before parent directory segments" do
    FileUtils.mkdir_p(File.join(root, "nested", "child"))
    target = File.join(root, "nested", "fixture.json")
    File.write(target, "nested")
    File.symlink(File.join(root, "nested", "child"), File.join(root, "link"))
    collector.start
    expect(File.read(File.join(root, "link", "..", "fixture.json"))).to eq("nested")
    expect(collector.stop).to include(target => true)
  end

  it "observes symlink target changes within one test" do
    link = File.join(root, "link")
    File.symlink(fixture, link)
    collector.start
    File.read(link)
    File.unlink(link)
    File.symlink(other_fixture, link)
    File.read(link)
    expect(collector.stop).to include(fixture => true, other_fixture => true)
  end

  it "does not treat command pipes as filenames" do
    collector.start
    Dir.chdir(root) do
      expect(IO.read("|printf fixture")).to eq("fixture")
      expect(IO.binread("|printf fixture")).to eq("fixture")
      expect(IO.readlines("|printf fixture")).to eq(["fixture"])
    end
    expect(collector.stop).to be_empty
  end

  it "supports literal pipe filenames through File.read" do
    path = File.join(root, "|fixture")
    File.write(path, "fixture")
    collector.start
    Dir.chdir(root) do
      expect(File.read("|fixture")).to eq("fixture")
      expect(Class.new(IO).read("|fixture")).to eq("fixture")
    end
    expect(collector.stop).to eq(path => true)
  end

  it "tracks write APIs conservatively without changing modes or return values" do
    collector.start
    expect(File.write(fixture, "first", mode: "a")).to eq(5)
    expect(File.binwrite(other_fixture, "second")).to eq(6)
    expect(collector.stop).to eq(fixture => true, other_fixture => true)
  end

  it "excludes outside paths and bundled gems with directory boundaries" do
    FileUtils.mkdir_p(File.join(root, "vendor"))
    FileUtils.mkdir_p(File.join(root, "vendor_extra"))
    ignored = File.join(root, "vendor", "fixture")
    included = File.join(root, "vendor_extra", "fixture")
    File.write(ignored, "ignored")
    File.write(included, "included")
    collector.start
    File.read(__FILE__)
    File.read(ignored)
    File.read(included)
    expect(collector.stop).to eq(included => true)
  end

  it "does not include files opened outside the collection window" do
    File.read(other_fixture)
    collector.start
    File.read(fixture)
    expect(collector.stop).to eq(fixture => true)
    File.read(other_fixture)
    collector.start
    expect(collector.stop).to be_empty
  end

  it "applies an optional session filter at the time of access" do
    enabled = false
    filtered = described_class.new(root: root, ignored_path: nil, threading_mode: :multi) { enabled }
    filtered.start
    File.read(fixture)
    enabled = true
    File.read(other_fixture)
    expect(filtered.stop).to eq(other_fixture => true)
  ensure
    filtered&.stop
  end

  it "does not attribute child-process reads to an inherited test collector" do
    collector.start
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      File.read(fixture)
      Marshal.dump(collector.stop, writer)
      writer.close
      exit! 0
    end
    writer.close
    expect(Marshal.load(reader)).to be_empty
    Process.wait(pid)
    expect(collector.stop).to be_empty
  ensure
    reader&.close
    writer&.close unless writer&.closed?
  end

  it "records reopened files and preserves the return value" do
    File.open(other_fixture) do |file|
      collector.start
      expect(file.reopen(fixture)).to equal(file)
      expect(collector.stop).to eq(fixture => true)
    end
  end

  it "does not treat file descriptors as paths" do
    File.open(fixture) do |file|
      collector.start
      File.open(file.fileno, autoclose: false) { |duplicate| expect(duplicate.read).not_to be_empty }
      expect(collector.stop).to be_empty
    end
  end

  it "includes background thread accesses in multi-threaded mode" do
    collector.start
    Thread.new { File.read(fixture) }.join
    expect(collector.stop).to eq(fixture => true)
  end

  context "in single-threaded mode" do
    let(:mode) { :single }

    it "isolates simultaneous collectors and includes other fibers on the owning thread" do
      collector.start
      other = described_class.new(root: root, ignored_path: nil, threading_mode: :single)
      other_coverage = Thread.new do
        other.start
        File.read(other_fixture)
        other.stop
      end.value
      Fiber.new { File.read(fixture) }.resume
      expect(collector.stop).to eq(fixture => true)
      expect(other_coverage).to eq(other_fixture => true)
    ensure
      other&.stop
    end
  end

  it "preserves IO results when dependency tracking fails" do
    collector.start
    allow(collector).to receive(:record).and_raise("tracking error")
    expect(Datadog.logger).to receive(:warn).with(/tracking error/)
    expect(File.read(fixture)).to eq("{\"value\":42}\n")
  end

  it "does not recursively collect logger file access" do
    collector.start
    allow(collector).to receive(:record).and_raise("tracking error")
    allow(Datadog.logger).to receive(:warn) { File.read(other_fixture) }
    expect(File.read(fixture)).to eq("{\"value\":42}\n")
    expect(Datadog.logger).to have_received(:warn).once
  end
end
