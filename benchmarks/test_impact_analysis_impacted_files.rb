# frozen_string_literal: true

# Measures the synchronous per-test TIA lifecycle through the coverage-writer
# handoff. Coverage serialization and transport run asynchronously in production
# and are intentionally excluded.

require "benchmark"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog"
require "datadog/ci/test"
require "datadog/ci/test_impact_analysis/component"
require "datadog/tracing/span_operation"

class BenchmarkRemoteConfiguration
  def itr_enabled?
    true
  end

  def tests_skipping_enabled?
    false
  end

  def code_coverage_enabled?
    true
  end
end

class BenchmarkCoverageWriter
  attr_reader :events_count, :last_event

  def initialize
    @events_count = 0
  end

  def write(event)
    @events_count += 1
    @last_event = event
  end
end

class BenchmarkTestSession
  def set_tag(_name, _value)
  end

  def distributed
    false
  end
end

class BenchmarkTestContext
  def incr_tests_skipped_by_tia_count
  end
end

def execute_test_body
  true
end

def build_test_impact_analysis(coverage_writer)
  test_impact_analysis = Datadog::CI::TestImpactAnalysis::Component.new(
    dd_env: "benchmark",
    coverage_writer: coverage_writer,
    enabled: true
  )
  test_impact_analysis.configure(BenchmarkRemoteConfiguration.new, BenchmarkTestSession.new)

  unless test_impact_analysis.code_coverage?
    raise "TIA coverage could not be enabled; run `bundle exec rake compile_ext`"
  end

  test_impact_analysis
end

def trace_tests(iterations, impacted_files, test_impact_analysis, coverage_writer)
  test_context = BenchmarkTestContext.new
  initial_events_count = coverage_writer.events_count

  iterations.times do
    tracer_span = Datadog::Tracing::SpanOperation.new("benchmark test")
    test = Datadog::CI::Test.new(tracer_span)
    test.set_tag(Datadog::CI::Ext::Test::TAG_NAME, "benchmark test")
    test.set_tag(Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::PASS)
    test.set_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID, "1")
    test.set_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID, "2")
    test.set_tag(
      Datadog::CI::Ext::Test::TAG_SOURCE_FILE,
      "benchmarks/test_impact_analysis_impacted_files.rb"
    )
    test.context_ids = []

    test_impact_analysis.on_test_started(test)
    execute_test_body
    test.add_impacted_files(impacted_files) unless impacted_files.empty?
    test_impact_analysis.on_test_finished(test, test_context)

    tracer_span.finish
  end

  events_count = coverage_writer.events_count - initial_events_count
  raise "wrote #{events_count} coverage events, expected #{iterations}" unless events_count == iterations

  missing_impacted_files = impacted_files.reject do |file_path|
    coverage_writer.last_event.coverage.key?(file_path)
  end
  unless missing_impacted_files.empty?
    raise "coverage event is missing #{missing_impacted_files.size} custom impacted files"
  end
end

iterations = Integer(ENV.fetch("ITERATIONS", "100000"))
impacted_files_count = Integer(ENV.fetch("IMPACTED_FILES", "100"))

raise "ITERATIONS must be positive" unless iterations.positive?
raise "IMPACTED_FILES must not be negative" if impacted_files_count.negative?
if impacted_files_count > Datadog::CI::Test::MAX_IMPACTED_FILES
  raise "IMPACTED_FILES must not exceed #{Datadog::CI::Test::MAX_IMPACTED_FILES}"
end

impacted_files = Array.new(impacted_files_count) do |index|
  "app/frontend/benchmark_component_#{index}.js"
end.freeze
coverage_only_writer = BenchmarkCoverageWriter.new
coverage_only_tia = build_test_impact_analysis(coverage_only_writer)
custom_files_writer = BenchmarkCoverageWriter.new
custom_files_tia = build_test_impact_analysis(custom_files_writer)

warmup_iterations = [iterations, 1000].min
trace_tests(warmup_iterations, [], coverage_only_tia, coverage_only_writer)
trace_tests(warmup_iterations, impacted_files, custom_files_tia, custom_files_writer)

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "Traced tests per scenario: #{iterations}"
puts "Normal TIA coverage: native collector"
puts "Custom impacted files per test: #{impacted_files.size}"
puts

Benchmark.bm(44) do |benchmark|
  GC.start

  benchmark.report("TIA coverage only") do
    trace_tests(iterations, [], coverage_only_tia, coverage_only_writer)
  end

  GC.start

  benchmark.report("TIA coverage + custom impacted files") do
    trace_tests(iterations, impacted_files, custom_files_tia, custom_files_writer)
  end
end
