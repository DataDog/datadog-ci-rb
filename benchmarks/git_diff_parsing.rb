# frozen_string_literal: true

# Run from the repository root:
#   bundle exec ruby benchmarks/git_diff_parsing.rb [samples=5]

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci"
require "datadog/ci/git/diff"

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

git_diff_output = +""
200.times do |f|
  git_diff_output << "diff --git a/app/models/model_#{f}.rb b/app/models/model_#{f}.rb\n"
  git_diff_output << "index 1234567..89abcdef 100644\n"
  git_diff_output << "--- a/app/models/model_#{f}.rb\n"
  git_diff_output << "+++ b/app/models/model_#{f}.rb\n"
  5.times do |h|
    git_diff_output << "@@ -#{h * 20 + 1},3 +#{h * 20 + 1},4 @@ class Model#{f}\n"
    18.times { |l| git_diff_output << "  def method_#{l}; #{l}; end\n" }
    git_diff_output << "+  def added_#{h}; true; end\n"
    git_diff_output << "~\n"
  end
end
git_diff_output.freeze

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}) | samples=#{samples}"
puts "-" * 96

measure("git_diff.parse_diff (20k lines x 5)", samples: samples) do
  5.times { Datadog::CI::Git::Diff.parse_diff_output(git_diff_output) }
end
