# frozen_string_literal: true

require "benchmark"
require "tmpdir"
require_relative "../lib/datadog/ci/test_impact_analysis/coverage/file_access"

# Run in a fresh process so baseline measurements precede hook installation.
# bundle exec ruby benchmarks/test_impact_analysis_file_access.rb [iterations]
iterations = Integer(ARGV.fetch(0, "20000"))
Dir.mktmpdir do |directory|
  root = File.realpath(directory)
  path = File.join(root, "fixture.json")
  File.write(path, '{"value":42}')
  collector = Datadog::CI::TestImpactAnalysis::Coverage::FileAccess.new(
    root: root, ignored_path: nil, threading_mode: :multi
  )

  [:baseline, :inactive, :active].each do |mode|
    if mode == :inactive
      collector.start
      collector.stop
    elsif mode == :active
      collector.start
    end
    1000.times { File.read(path) }
    samples = 5.times.map do
      GC.start
      allocations = GC.stat(:total_allocated_objects)
      elapsed = Benchmark.realtime { iterations.times { File.read(path) } }
      allocations = GC.stat(:total_allocated_objects) - allocations
      [elapsed * 1_000_000 / iterations, allocations.to_f / iterations]
    end
    puts "%s: %.2f us/read, %.2f allocations/read (median of 5)" % [mode, samples.map(&:first).sort[2], samples.map(&:last).sort[2]]
  end
  raise "Fixture dependency was not recorded" unless collector.stop.key?(path)
end
