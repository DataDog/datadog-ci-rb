# frozen_string_literal: true

require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
require_relative "app/model/my_model"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::DDCov, "adversarial concurrency" do
  # Forks contain leaked native hooks and bound deadlocks to the helper's timeout.
  # Queues force the relevant schedule; sleeps and scheduler luck are unnecessary.
  let(:root) { File.expand_path("concurrency_sources", __dir__) }
  let(:paths) { %w[first second late].map { |name| File.join(root, "#{name}.rb") } }
  let(:sources) { paths.map { |path| RubyVM::InstructionSequence.compile("Thread.pass\n", path, path) } }

  def collector(mode = :multi)
    described_class.new(root: root, threading_mode: mode, use_allocation_tracing: false)
  end

  it "makes repeated start and stop harmless to other collectors" do
    expect_in_fork do
      first, second = collector, collector
      code = sources
      first.start
      first.start
      second.start
      code[0].eval
      expect(first.stop.keys).to contain_exactly(paths[0])
      expect(first.stop).to be_empty
      code[1].eval
      expect(second.stop.keys).to contain_exactly(paths[0], paths[1])
      first.start
      code[2].eval
      expect(first.stop.keys).to contain_exactly(paths[2])
    end
  end

  it "keeps an overlapping collector's line hook alive when another thread stops" do
    expect_in_fork do
      first, second = collector, collector
      code = sources
      ready, release = Queue.new, Queue.new
      first.start
      worker = Thread.new do
        second.start
        code[0].eval
        ready << true
        release.pop
        code[1].eval
        second.stop
      end
      ready.pop
      first_result = first.stop
      release << true
      second_result = worker.value

      expect(first_result.keys).to contain_exactly(paths[0])
      expect(second_result.keys).to contain_exactly(paths[0], paths[1])
    end
  end

  it "does not let an idle collector on another thread disable active coverage" do
    expect_in_fork do
      active, idle = collector, collector
      code = sources
      active.start
      code[0].eval
      Thread.new { idle.stop }.value
      code[1].eval
      result = active.stop

      expect(result.keys).to contain_exactly(paths[0], paths[1])
    end
  end

  it "keeps a sibling fiber's collector alive when another collector stops" do
    expect_in_fork do
      first, second = collector(:single), collector(:single)
      code = sources
      fiber = Fiber.new do
        second.start
        code[0].eval
        Fiber.yield
        code[1].eval
        second.stop
      end
      first.start
      fiber.resume
      first.stop
      expect(fiber.resume.keys).to contain_exactly(paths[0], paths[1])
    end
  end

  it "keeps another thread's allocation hook alive after stopping an overlapping collector" do
    expect_in_fork do
      options = {root: File.expand_path("app", __dir__), threading_mode: :multi, use_allocation_tracing: true}
      first, second = described_class.new(options), described_class.new(options)
      ready, release = Queue.new, Queue.new
      first.start
      worker = Thread.new do
        second.start
        ready << true
        release.pop
        MyModel.new
        second.stop
      end
      ready.pop
      first.stop
      release << true
      expect(worker.value.keys).to include(File.expand_path("app/model/my_model.rb", __dir__))
    end
  end
end
