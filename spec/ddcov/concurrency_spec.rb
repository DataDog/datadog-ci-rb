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

  it "isolates single-mode workers across repeated windows and GC compaction" do
    expect_in_fork do
      code = sources
      ready = Queue.new
      releases = Array.new(3) { Queue.new }
      workers = releases.each_with_index.map do |release, index|
        Thread.new do
          cov = collector(:single)
          Array.new(8) do
            cov.start
            code[index].eval
            ready << true
            release.pop
            code[index].eval
            cov.stop.keys
          end
        end
      end
      8.times do
        3.times { ready.pop }
        GC.start
        GC.compact if GC.respond_to?(:compact)
        releases.each { |release| release << true }
      end
      workers.each_with_index do |worker, index|
        expect(worker.value).to eq(Array.new(8) { [paths[index]] })
      end
    end
  end

  it "rejects a foreign-thread stop without damaging the single-mode owner" do
    expect_in_fork do
      cov = collector(:single)
      code = sources
      cov.start
      Thread.new do
        expect { cov.stop }.to raise_error(RuntimeError, "Coverage was not started by this thread")
      end.value
      code[0].eval
      expect(cov.stop.keys).to contain_exactly(paths[0])
    end
  end

  it "shows that single mode omits even a joined child thread's dependencies" do
    expect_in_fork do
      cov = collector(:single)
      code = sources
      cov.start
      code[0].eval
      Thread.new { code[1].eval }.value
      expect(cov.stop.keys).to contain_exactly(paths[0])
    end
  end

  it "shows that single mode observes sibling fibers on the same Ruby thread" do
    expect_in_fork do
      cov = collector(:single)
      code = sources
      cov.start
      Fiber.new { code[1].eval }.resume
      expect(cov.stop.keys).to contain_exactly(paths[1])
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

  it "shows that a late background job is attributed to the next collection window" do
    expect_in_fork do
      cov = collector
      code = sources
      ready, release = Queue.new, Queue.new
      cov.start
      worker = Thread.new do
        ready << true
        release.pop
        code[2].eval
      end
      ready.pop
      code[0].eval
      first_result = cov.stop
      cov.start
      release << true
      worker.value
      second_result = cov.stop

      expect(first_result.keys).to contain_exactly(paths[0])
      expect(second_result.keys).to contain_exactly(paths[2])
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
