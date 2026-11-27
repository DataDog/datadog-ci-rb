# frozen_string_literal: true

# Run from the repository root (after `bundle exec rake compile`):
#   bundle exec ruby benchmarks/native_coverage_and_file_deps.rb [samples=5]

require "rbconfig"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci"
require "datadog/ci/git/local_repository"
require "datadog/ci/test_impact_analysis/coverage/opened_files_collector"

begin
  require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
rescue LoadError => e
  abort "Native extension is not compiled (run `bundle exec rake compile`): #{e.message}"
end

samples = Integer(ARGV.fetch(0, "5"))

def measure(label, samples:)
  yield

  times = []
  allocs = []

  samples.times do
    GC.start
    alloc_before = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    times << elapsed
    allocs << (GC.stat(:total_allocated_objects) - alloc_before)
  end

  mid = samples / 2
  median_ms = times.sort[mid] * 1000.0
  min_ms = times.min * 1000.0
  median_allocs = allocs.sort[mid]

  puts format("%-42s median: %8.2f ms (min: %8.2f ms) | allocs: %10d", label, median_ms, min_ms, median_allocs)
end

repo_root = Datadog::CI::Git::LocalRepository.root
coverage_hash = (0...200).each_with_object({}) do |i, h|
  h["#{repo_root}/app/models/model_#{i}.rb"] = true
end.freeze
custom_files = Array.new(20) { |i| "app/javascript/component_#{i}.js" }.freeze

outside_paths = [
  "/usr/lib/libSystem.B.dylib",
  "/tmp/nonexistent_bench_file.txt",
  File.join(RbConfig::CONFIG["rubylibdir"], "json.rb")
].freeze
inside_path = File.join(repo_root, "README.md")

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}) | samples=#{samples}"
puts "-" * 98

measure("file_serialization.pack_files (5k x 220)", samples: samples) do
  5_000.times do
    Datadog::CI::FileSerialization.pack_files(coverage_hash, custom_files, repo_root)
  end
end

measure("ddcov start/stop single (20k)", samples: samples) do
  cov = Datadog::CI::TestImpactAnalysis::Coverage::DDCov.new(
    root: repo_root,
    threading_mode: :single,
    use_allocation_tracing: false
  )
  20_000.times do
    cov.start
    cov.stop
  end
end

measure("opened_files_collector (5k cycles)", samples: samples) do
  collector = Datadog::CI::TestImpactAnalysis::Coverage::OpenedFilesCollector.new(
    root: repo_root,
    ignored_path: nil
  )
  5_000.times do
    collector.start
    outside_paths.each { |p| collector.record(p) }
    collector.record(inside_path)
    collector.stop
  end
end
