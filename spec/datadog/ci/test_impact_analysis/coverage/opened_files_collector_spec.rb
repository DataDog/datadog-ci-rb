# frozen_string_literal: true

require "tmpdir"
require "datadog/ci/test_impact_analysis/coverage/opened_files_collector"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::OpenedFilesCollector do
  subject(:collector) { described_class.new(root: directory, ignored_path: nil) }

  let(:directory) { Dir.mktmpdir("opened-files-") }
  let(:path) { File.join(directory, "fixture.txt") }
  let(:other_path) { File.join(directory, "other.txt") }

  before do
    File.write(path, "fixture")
    File.write(other_path, "other")
  end

  after { FileUtils.remove_entry(directory) }

  it "collects reads from an existing worker and a child thread" do
    work = Queue.new
    worker = Thread.new { collector.prepare_file_read(work.pop) }
    collector.start
    work << path
    worker.value
    Thread.new { collector.prepare_file_read(other_path) }.value

    expect(collector.stop).to eq(path => true, other_path => true)
  ensure
    worker&.kill
    worker&.join
  end

  it "ignores reads outside collection and starts a fresh result after stop" do
    collector.record(other_path)
    collector.start
    collector.record(path)
    expect(collector.stop).to eq(path => true)
    collector.record(other_path)
    collector.start
    expect(collector.stop).to be_empty
    expect(collector.stop).to be_empty
  end

  it "preserves collected files when started twice and deduplicates reads" do
    collector.start
    collector.record(path)
    collector.start
    collector.record(path)
    expect(collector.stop).to eq(path => true)
  end

  it "does not resolve or coerce paths without an active collection" do
    argument = double("path")
    expect(argument).not_to receive(:to_path)
    expect_any_instance_of(Datadog::CI::TestImpactAnalysis::Coverage::FileDependencies).not_to receive(:paths_for)
    expect(collector.prepare_file_read(argument)).to equal(argument)
    collector.record(path)
  end

  it "preserves errors from customer path conversion" do
    argument = double("path")
    expect(argument).to receive(:to_path).and_raise(TypeError, "customer error")
    collector.start
    expect { collector.prepare_file_read(argument) }.to raise_error(TypeError, "customer error")
  end

  it "records one read in every overlapping collection" do
    ready = Queue.new
    finish = Queue.new
    collector.start
    worker = Thread.new do
      collector.start
      ready << true
      finish.pop
      collector.stop
    end
    ready.pop
    collector.record(path)
    expect(collector.stop).to eq(path => true)
    collector.record(other_path)
    finish << true
    expect(worker.value).to eq(path => true, other_path => true)
  ensure
    worker&.kill
    worker&.join
  end

  it "keeps separate collection lifecycles for fibers on the same thread" do
    collector.start
    fiber = Fiber.new do
      collector.start
      collector.record(path)
      Fiber.yield
      collector.stop
    end
    fiber.resume
    expect(collector.stop).to eq(path => true)
    collector.record(other_path)
    expect(fiber.resume).to eq(path => true, other_path => true)
  end

  it "does not change a stopped result or leak delayed resolution into the next collection" do
    resolving = Queue.new
    finish = Queue.new
    allow_any_instance_of(Datadog::CI::TestImpactAnalysis::Coverage::FileDependencies)
      .to receive(:paths_for).with(path) do
        resolving << true
        finish.pop
        [path]
      end
    collector.start
    worker = Thread.new { collector.record(path) }
    resolving.pop
    stopped = collector.stop
    collector.start
    finish << true
    worker.value

    expect(stopped).to be_empty
    expect(collector.stop).to be_empty
  ensure
    worker&.kill
    worker&.join
  end
end
