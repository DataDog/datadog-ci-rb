# frozen_string_literal: true

# Measures the TIA lifecycle and MessagePack serialization CPU cost. Production
# performs serialization on a writer thread, but it still consumes CPU in the
# same Ruby process.

require "benchmark"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog"
require "datadog/ci/test"
require "datadog/ci/test_suite"
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
  attr_reader :events_count, :last_payload

  def initialize
    @events_count = 0
  end

  def write(event)
    @events_count += 1
    @last_payload = MessagePack.pack(event)
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

module BenchmarkTestImpactAnalysis
  attr_accessor :benchmark_test_impact_analysis

  private

  def test_impact_analysis
    benchmark_test_impact_analysis
  end
end

class BenchmarkTest < Datadog::CI::Test
  include BenchmarkTestImpactAnalysis

  attr_accessor :benchmark_test_suite

  def test_suite
    benchmark_test_suite
  end
end

class BenchmarkTestSuite < Datadog::CI::TestSuite
  include BenchmarkTestImpactAnalysis
end

def execute_test_body
  true
end

def build_test_impact_analysis(coverage_writer, test_skipping_mode)
  test_impact_analysis = Datadog::CI::TestImpactAnalysis::Component.new(
    dd_env: "benchmark",
    coverage_writer: coverage_writer,
    enabled: true,
    test_skipping_mode: test_skipping_mode
  )
  test_impact_analysis.configure(BenchmarkRemoteConfiguration.new, BenchmarkTestSession.new)

  unless test_impact_analysis.code_coverage?
    raise "TIA coverage could not be enabled; run `bundle exec rake compile_ext`"
  end

  test_impact_analysis
end

def build_test_suite(suite_impacted_files, test_impact_analysis)
  tracer_span = Datadog::Tracing::SpanOperation.new("benchmark suite")
  tracer_span.set_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID, "1")
  test_suite = BenchmarkTestSuite.new(tracer_span)
  test_suite.benchmark_test_impact_analysis = test_impact_analysis
  test_suite.add_impacted_files(suite_impacted_files) unless suite_impacted_files.empty?
  test_suite
end

def build_test(test_suite, test_impacted_files, test_impact_analysis)
  tracer_span = Datadog::Tracing::SpanOperation.new("benchmark test")
  test = BenchmarkTest.new(tracer_span)
  test.benchmark_test_suite = test_suite
  test.benchmark_test_impact_analysis = test_impact_analysis
  test.set_tag(Datadog::CI::Ext::Test::TAG_NAME, "benchmark test")
  test.set_tag(Datadog::CI::Ext::Test::TAG_STATUS, Datadog::CI::Ext::Test::Status::PASS)
  test.set_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID, "1")
  test.set_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID, test_suite.id.to_s)
  test.set_tag(
    Datadog::CI::Ext::Test::TAG_SOURCE_FILE,
    "benchmarks/test_impact_analysis_impacted_files.rb"
  )
  test.context_ids = []
  test.add_impacted_files(test_impacted_files) unless test_impacted_files.empty?
  test
end

def validate_impacted_files(payload, expected_impacted_files)
  payload_files = MessagePack.unpack(payload).fetch("files")
  payload_filenames = payload_files.map { |file| file.fetch("filename") }
  invalid_files = expected_impacted_files.reject { |file| payload_filenames.count(file) == 1 }
  return if invalid_files.empty?

  raise "coverage event is missing or duplicates #{invalid_files.size} custom impacted files"
end

def trace_tests_in_test_mode(
  iterations,
  test_impacted_files_by_test,
  suite_impacted_files,
  test_impact_analysis,
  coverage_writer
)
  test_context = BenchmarkTestContext.new
  initial_events_count = coverage_writer.events_count
  test_suite = build_test_suite(suite_impacted_files, test_impact_analysis)

  iterations.times do |test_index|
    test_impacted_files = test_impacted_files_by_test[test_index % test_impacted_files_by_test.size]
    test = build_test(test_suite, test_impacted_files, test_impact_analysis)

    test_impact_analysis.on_test_started(test)
    execute_test_body
    test_impact_analysis.on_test_finished(test, test_context)

    test.tracer_span.finish
  end

  events_count = coverage_writer.events_count - initial_events_count
  raise "wrote #{events_count} coverage events, expected #{iterations}" unless events_count == iterations

  validate_impacted_files(
    coverage_writer.last_payload,
    test_impacted_files_by_test[(iterations - 1) % test_impacted_files_by_test.size] | suite_impacted_files
  )
end

def trace_tests_in_suite_mode(
  iterations,
  suites_count,
  test_impacted_files_by_test,
  suite_impacted_files,
  test_impact_analysis,
  coverage_writer
)
  test_context = BenchmarkTestContext.new
  initial_events_count = coverage_writer.events_count
  tests_per_suite, suites_with_extra_test = iterations.divmod(suites_count)

  suites_count.times do |suite_index|
    test_suite = build_test_suite(suite_impacted_files, test_impact_analysis)
    test_impact_analysis.on_test_suite_started(test_suite)
    current_suite_tests = tests_per_suite
    current_suite_tests += 1 if suite_index < suites_with_extra_test

    current_suite_tests.times do |test_index|
      test_impacted_files = test_impacted_files_by_test[test_index % test_impacted_files_by_test.size]
      test = build_test(test_suite, test_impacted_files, test_impact_analysis)

      test_impact_analysis.on_test_started(test)
      execute_test_body
      test_impact_analysis.on_test_finished(test, test_context)

      test.tracer_span.finish
    end

    test_impact_analysis.on_test_suite_finished(test_suite, test_context)
  end

  events_count = coverage_writer.events_count - initial_events_count
  unless events_count == suites_count
    raise "wrote #{events_count} coverage events, expected #{suites_count}"
  end

  validate_impacted_files(
    coverage_writer.last_payload,
    Array.new(tests_per_suite) do |test_index|
      test_impacted_files_by_test[test_index % test_impacted_files_by_test.size]
    end.flatten.uniq | suite_impacted_files
  )
end

iterations = Integer(ENV.fetch("ITERATIONS", "100000"))
suites_count = Integer(ENV.fetch("SUITES", "10000"))
impacted_files_count = Integer(ENV.fetch("IMPACTED_FILES", "100"))

raise "ITERATIONS must be positive" unless iterations.positive?
raise "SUITES must be positive" unless suites_count.positive?
raise "SUITES must not exceed ITERATIONS" if suites_count > iterations
raise "IMPACTED_FILES must not be negative" if impacted_files_count.negative?

shared_test_impacted_files_count = impacted_files_count / 2
unique_test_impacted_files_count = impacted_files_count - shared_test_impacted_files_count
shared_test_impacted_files = Array.new(shared_test_impacted_files_count) do |index|
  "app/frontend/benchmark_component_#{index}.js"
end.freeze
maximum_tests_per_suite = (iterations.to_f / suites_count).ceil
# Reuse variants across suites to keep benchmark setup memory bounded. Within
# each suite, half of every test's paths are unique to that test.
test_impacted_files_by_test = Array.new(maximum_tests_per_suite) do |test_index|
  unique_files = Array.new(unique_test_impacted_files_count) do |file_index|
    "app/frontend/benchmark_test_#{test_index}_component_#{file_index}.js"
  end
  (shared_test_impacted_files + unique_files).freeze
end.freeze
overlapping_files_count = shared_test_impacted_files_count
suite_impacted_files = (
  shared_test_impacted_files.first(overlapping_files_count) +
  Array.new(impacted_files_count - overlapping_files_count) do |index|
    "app/frontend/benchmark_suite_#{index}.js"
  end
).freeze

test_mode = Datadog::CI::Ext::Test::TIATestSkippingMode::TEST
suite_mode = Datadog::CI::Ext::Test::TIATestSkippingMode::SUITE

test_mode_coverage_writer = BenchmarkCoverageWriter.new
test_mode_coverage_tia = build_test_impact_analysis(test_mode_coverage_writer, test_mode)
test_mode_custom_writer = BenchmarkCoverageWriter.new
test_mode_custom_tia = build_test_impact_analysis(test_mode_custom_writer, test_mode)
suite_mode_coverage_writer = BenchmarkCoverageWriter.new
suite_mode_coverage_tia = build_test_impact_analysis(suite_mode_coverage_writer, suite_mode)
suite_mode_custom_writer = BenchmarkCoverageWriter.new
suite_mode_custom_tia = build_test_impact_analysis(suite_mode_custom_writer, suite_mode)

warmup_iterations = [iterations, 1000].min
warmup_suites_count = [(warmup_iterations * suites_count) / iterations, 1].max
trace_tests_in_test_mode(warmup_iterations, [[]], [], test_mode_coverage_tia, test_mode_coverage_writer)
trace_tests_in_test_mode(
  warmup_iterations,
  test_impacted_files_by_test,
  suite_impacted_files,
  test_mode_custom_tia,
  test_mode_custom_writer
)
trace_tests_in_suite_mode(
  warmup_iterations,
  warmup_suites_count,
  [[]],
  [],
  suite_mode_coverage_tia,
  suite_mode_coverage_writer
)
trace_tests_in_suite_mode(
  warmup_iterations,
  warmup_suites_count,
  test_impacted_files_by_test,
  suite_impacted_files,
  suite_mode_custom_tia,
  suite_mode_custom_writer
)

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "Traced tests per scenario: #{iterations}"
puts "Suites in suite-mode scenarios: #{suites_count}"
puts "Normal TIA coverage: native collector"
puts "MessagePack serialization: every coverage event"
puts "Custom impacted files per test: #{impacted_files_count}"
puts "Custom impacted files unique per test within a suite: #{unique_test_impacted_files_count}"
puts "Custom impacted files per suite: #{suite_impacted_files.size}"
puts "Overlapping test/suite impacted files: #{overlapping_files_count}"
puts

Benchmark.bm(54) do |benchmark|
  GC.start

  benchmark.report("Test mode: TIA coverage only") do
    trace_tests_in_test_mode(iterations, [[]], [], test_mode_coverage_tia, test_mode_coverage_writer)
  end

  GC.start

  benchmark.report("Test mode: TIA coverage + test/suite impacted files") do
    trace_tests_in_test_mode(
      iterations,
      test_impacted_files_by_test,
      suite_impacted_files,
      test_mode_custom_tia,
      test_mode_custom_writer
    )
  end

  GC.start

  benchmark.report("Suite mode: TIA coverage only") do
    trace_tests_in_suite_mode(
      iterations,
      suites_count,
      [[]],
      [],
      suite_mode_coverage_tia,
      suite_mode_coverage_writer
    )
  end

  GC.start

  benchmark.report("Suite mode: TIA coverage + test/suite impacted files") do
    trace_tests_in_suite_mode(
      iterations,
      suites_count,
      test_impacted_files_by_test,
      suite_impacted_files,
      suite_mode_custom_tia,
      suite_mode_custom_writer
    )
  end
end
