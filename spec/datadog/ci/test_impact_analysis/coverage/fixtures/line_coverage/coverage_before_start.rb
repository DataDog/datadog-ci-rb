# frozen_string_literal: true

# Run by line_coverage_spec.rb in a child process, with Ruby's Coverage on and warnings
# verbose. Starts the collector after a file loaded, and prints whether the collector
# compiled that file, and whether Ruby's Coverage results stayed the same.
require "coverage"
require "datadog/ci/test_impact_analysis/coverage/line_coverage"
require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

coverage = Datadog::CI::TestImpactAnalysis::Coverage
root = ARGV.fetch(0)
path = File.join(__dir__, "warns_on_load.rb")
Coverage.start(lines: true, branches: true, methods: true)
$VERBOSE = true
require path
before = Coverage.peek_result
coverage::LineCoverage.start(root: root, ignored_paths: [])
after = Coverage.peek_result
compiled = coverage::LineCollector.stats.fetch(:loaded_lines_left_by_file).key?(path.delete_prefix(File.join(root, "")))
print [compiled, after.keys == before.keys, after.fetch(path) == before.fetch(path)].inspect
