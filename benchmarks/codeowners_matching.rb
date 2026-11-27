# frozen_string_literal: true

# Run from the repository root:
#   bundle exec ruby benchmarks/codeowners_matching.rb [samples=5]

require "fileutils"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci"
require "datadog/ci/codeowners/matcher"

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

dir = Dir.mktmpdir("dd-ci-bench-codeowners-")
at_exit { FileUtils.rm_rf(dir) }

codeowners_path = File.join(dir, "CODEOWNERS")
File.open(codeowners_path, "w") do |f|
  f.puts "* @org/default-team"
  500.times do |i|
    case i % 4
    when 0 then f.puts "/app/services/domain_#{i}/ @org/team-#{i % 20}"
    when 1 then f.puts "/spec/models/group_#{i}/*.rb @org/models-#{i % 15}"
    when 2 then f.puts "components/pkg_#{i}/sub/**/spec.rb @org/pkg-#{i % 10}"
    else f.puts "/spec/requests/api_v#{i}/endpoint_#{i}_spec.rb @org/api-#{i % 12}"
    end
  end
end

cold_files = Array.new(500) { |i| "spec/models/group_#{i % 100}/file_#{i}_spec.rb" }.freeze
workload_files = Array.new(5_000) do |i|
  file_idx = i % 100
  case file_idx % 4
  when 0 then "spec/models/group_#{file_idx * 4 + 1}/user_spec.rb"
  when 1 then "spec/requests/api_v#{file_idx * 4 + 3}/endpoint_#{file_idx * 4 + 3}_spec.rb"
  when 2 then "spec/unmatched/feature_#{file_idx}_spec.rb"
  else "app/services/domain_#{file_idx * 4}/worker_spec.rb"
  end
end.freeze

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}) | samples=#{samples}"
puts "-" * 96

measure("codeowners.list_owners (cold 500x500)", samples: samples) do
  matcher = Datadog::CI::Codeowners::Matcher.new(codeowners_path)
  cold_files.each { |path| matcher.list_owners(path) }
end

measure("codeowners.list_owners (5k x 500)", samples: samples) do
  matcher = Datadog::CI::Codeowners::Matcher.new(codeowners_path)
  workload_files.each { |path| matcher.list_owners(path) }
end
