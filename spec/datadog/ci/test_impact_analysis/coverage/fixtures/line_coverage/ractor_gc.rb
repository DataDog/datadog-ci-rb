# frozen_string_literal: true

# Run by line_coverage_spec.rb in a child process, so that the spec process starts no
# Ractor. Prints whether the collector saw the first Ractors, then the lines of this file
# that the second test ran, then those that the third test ran.
require "datadog/ci/test_impact_analysis/coverage/line_coverage"
require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

Warning[:experimental] = false

def run_ractor
  ractor = Ractor.new { :done }
  ractor.respond_to?(:value) ? ractor.value : ractor.take
end

def after_collection
  :after_collection
end

def after_collection_in_test
  :after_collection_in_test
end

coverage = Datadog::CI::TestImpactAnalysis::Coverage
root = ARGV.fetch(0)
file = File.realpath(__FILE__).delete_prefix(File.join(root, ""))
lines = lambda do |packed|
  bitmap = coverage::LineFiles.unpack(packed)[file]
  bitmap ? coverage::LineFiles.lines(bitmap).join(",") : ""
end

line_coverage = coverage::LineCoverage.start(root: root, ignored_paths: [])
# No GC step runs while these Ractors run.
GC.disable
line_coverage.start_test(1)
3.times { run_ractor }
line_coverage.finish_test(1, [])
puts coverage::LineCollector.stats.fetch(:ractor_seen)
GC.enable
# Frees the finished Ractors between two tests.
2.times { GC.start }
line_coverage.start_test(2)
after_collection
_count, packed = line_coverage.finish_test(2, [])
puts lines.call(packed)
line_coverage.start_test(3)
3.times { run_ractor }
# Frees them during the test.
2.times { GC.start }
after_collection_in_test
_count, packed = line_coverage.finish_test(3, [])
puts lines.call(packed)
