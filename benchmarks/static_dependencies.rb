# frozen_string_literal: true

# Run from the repository root:
#   bundle exec ruby benchmarks/static_dependencies.rb [samples=5]

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci"
require "datadog/ci/git/local_repository"
require "datadog/ci/source_code/static_dependencies"

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

  puts format("%-40s median: %8.2f ms (min: %8.2f ms) | allocs: %10d", label, median_ms, min_ms, median_allocs)
end

repo_root = Datadog::CI::Git::LocalRepository.root

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}) | samples=#{samples}"
puts "-" * 96

unless Datadog::CI::SourceCode::ISeqCollector::STATIC_DEPENDENCIES_EXTRACTION_AVAILABLE
  abort "Static dependencies extraction is not available on this Ruby version."
end

measure("static_dependencies.populate!", samples: samples) do
  Datadog::CI::SourceCode::StaticDependencies.populate!(repo_root)
end
