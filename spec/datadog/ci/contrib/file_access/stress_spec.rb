# frozen_string_literal: true

require "tmpdir"
require "timeout"
require_relative "../../../../support/file_dependency_stress"

RSpec.describe "File dependency coverage under filesystem and GC stress" do
  include_context "CI mode activated"

  # Do not inherit a native collector configured for another spec's root.
  around { |example| Thread.new { example.run }.value }

  let(:itr_enabled) { true }
  let(:code_coverage_enabled) { true }
  let(:root) { Datadog::CI::Git::LocalRepository.root }
  let(:directory) { Dir.mktmpdir("file-dependency-stress-", root) }
  let(:events) { Queue.new }

  after { FileUtils.remove_entry(directory) }

  it "opens unusual valid paths concurrently and preserves every serialized dependency" do
    paths = FileDependencyStress.build(directory)
    component = Datadog.send(:components).test_impact_analysis
    allow(component).to receive(:write) { |event| events << MessagePack.unpack(MessagePack.pack(event)) }
    test_tracing.start_test_session
    test_tracing.start_test_suite("file stress")

    expected = paths.flat_map { |path| [File.absolute_path(path), File.realpath(path)] }.uniq
    expected.map! { |path| path.delete_prefix(root + "/") }
    prefix = directory.delete_prefix(root + "/") + "/"
    fixture_files = ->(event) { event.fetch("files").map { |file| file.fetch("filename") }.select { |path| path.start_with?(prefix) } }
    ready = Queue.new
    start = Queue.new
    workers = []

    # A stable cwd lets each worker exercise relative and absolute names without
    # racing process-wide chdir. Every worker has its own active test/collector.
    Dir.chdir(directory) do
      inputs = paths + paths.map { |path| "./" + path.delete_prefix(directory + "/") }
      # Valgrind makes forced GC and concurrent filesystem calls much slower.
      Timeout.timeout(120) do
        workers = [:open, :new, :read, :binread].map do |operation|
          Thread.new do
            2.times do |round|
              test_tracing.trace_test("#{operation} stress #{round}", "file stress") do
                if round.zero?
                  ready << true
                  start.pop
                end
                3.times do
                  inputs.each do |path|
                    expect(FileDependencyStress.read(path.dup.freeze, operation)).to eq(FileDependencyStress::CONTENTS)
                  end
                end
              end
            end
          end
        end
        workers.size.times { ready.pop }
        workers.size.times { start << true }
        3.times do
          if GC.respond_to?(:verify_compaction_references)
            GC.verify_compaction_references(double_heap: true)
          else
            GC.start
          end
          Thread.pass
        end
        workers.each(&:value)
      end
    end

    expect(events.size).to eq(8)
    8.times { expect(fixture_files.call(events.pop(true))).to match_array(expected) }
    test_tracing.trace_test("no file reads", "file stress") {}
    expect(events.size).to eq(1)
    expect(fixture_files.call(events.pop(true))).to be_empty
  ensure
    workers&.each do |worker|
      worker.kill if worker.alive?
      worker.join
    end
  end
end
