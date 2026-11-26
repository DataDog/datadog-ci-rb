# frozen_string_literal: true

# Run by line_coverage_spec.rb in a child process, so that the spec process starts no
# Ractor. Prints the lines of this file that the second test ran.
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

coverage = Datadog::CI::TestImpactAnalysis::Coverage
root = ARGV.fetch(0)
line_coverage = coverage::LineCoverage.start(root: root, ignored_paths: [])
line_coverage.start_test(1)
3.times { run_ractor }
line_coverage.finish_test(1, [])
# Frees the finished Ractors.
2.times { GC.start }
line_coverage.start_test(2)
after_collection
_count, packed = line_coverage.finish_test(2, [])
bitmap = coverage::LineFiles.unpack(packed)[File.realpath(__FILE__).delete_prefix(File.join(root, ""))]
print bitmap ? coverage::LineFiles.lines(bitmap).join(",") : ""
