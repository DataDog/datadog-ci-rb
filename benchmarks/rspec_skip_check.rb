# frozen_string_literal: true

# Run from the repository root:
#   bundle exec ruby benchmarks/rspec_skip_check.rb [samples=5]

require "rspec/core"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci"
require "datadog/ci/contrib/rspec/patcher"

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

  puts format("%-44s median: %8.2f ms (min: %8.2f ms) | allocs: %10d", label, median_ms, min_ms, median_allocs)
end

Datadog.configure do |c|
  c.telemetry.enabled = false
  c.diagnostics.startup_logs.enabled = false
  c.api_key = "local-benchmark"
  c.ci.enabled = true
  c.ci.agentless_mode_enabled = true
  c.ci.discard_traces = true
  c.ci.git_metadata_upload_enabled = false
end

Datadog::CI::Contrib::RSpec::Patcher.patch

groups = Array.new(50) do |g|
  ::RSpec.describe "BenchmarkGroup#{g}" do
    4.times do |sub|
      context "sub context #{sub}" do
        5.times do |ex|
          it("checks behavior #{ex}") { expect(1).to eq(1) }
        end
      end
    end
  end
end.freeze

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}) | samples=#{samples}"
puts "-" * 100

measure("rspec all_examples_skipped (250g x 20)", samples: samples) do
  20.times do
    groups.each do |group|
      group.send(:all_examples_skipped_by_datadog?)
      group.children.each { |child| child.send(:all_examples_skipped_by_datadog?) }
    end
  end
end
