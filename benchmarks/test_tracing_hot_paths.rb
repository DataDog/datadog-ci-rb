# frozen_string_literal: true

# Run from the repository root:
#   bundle exec ruby benchmarks/test_tracing_hot_paths.rb [samples=5]

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci"
require "datadog/tracing/span_operation"

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

Datadog.configure do |c|
  c.telemetry.enabled = false
  c.diagnostics.startup_logs.enabled = false
  c.api_key = "local-benchmark"
  c.ci.enabled = true
  c.ci.agentless_mode_enabled = true
  c.ci.discard_traces = true
  c.ci.git_metadata_upload_enabled = false
end

tracer_span = Datadog::Tracing::SpanOperation.new("benchmark_test", type: Datadog::CI::Ext::AppTypes::TYPE_TEST)
tracer_span.set_tags(
  Datadog::CI::Ext::Test::TAG_NAME => "creates a valid record",
  Datadog::CI::Ext::Test::TAG_SUITE => "UserSpec at ./spec/models/user_spec.rb",
  Datadog::CI::Ext::Test::TAG_SOURCE_FILE => "spec/models/user_spec.rb",
  Datadog::CI::Ext::Test::TAG_SOURCE_START => "42",
  Datadog::CI::Ext::Test::TAG_SOURCE_END => "55",
  Datadog::CI::Ext::Test::TAG_STATUS => Datadog::CI::Ext::Test::Status::PASS
)
test_span = Datadog::CI::Test.new(tracer_span)

tag_keys = [
  Datadog::CI::Ext::Test::TAG_NAME,
  Datadog::CI::Ext::Test::TAG_SUITE,
  Datadog::CI::Ext::Test::TAG_SOURCE_FILE,
  Datadog::CI::Ext::Test::TAG_STATUS,
  Datadog::CI::Ext::Test::TAG_IS_RETRY,
  Datadog::CI::Ext::Test::TAG_IS_QUARANTINED,
  Datadog::CI::Ext::Test::TAG_IS_TEST_DISABLED,
  Datadog::CI::Ext::Test::TAG_ITR_SKIPPED_BY_ITR,
  Datadog::CI::Ext::Git::TAG_COMMIT_SHA,
  Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID
].freeze

class DummyKnownTestsClient
  def fetch(_session)
    Set.new
  end
end

class DummyCodeowners
  OWNERS = ["@org/team"].freeze

  def list_owners(_path)
    OWNERS
  end
end

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}) | samples=#{samples}"
puts "-" * 96

measure("span.get_tag (200k reads)", samples: samples) do
  20_000.times do
    tag_keys.each { |k| test_span.get_tag(k) }
  end
end

measure("test_tracing lifecycle (2k tests)", samples: samples) do
  component = Datadog::CI::TestTracing::Component.new(
    known_tests_client: DummyKnownTestsClient.new,
    codeowners: DummyCodeowners.new
  )
  suite_name = "UsersController at ./spec/controllers/users_controller_spec.rb"
  suite_span = component.start_test_suite(
    suite_name,
    tags: {Datadog::CI::Ext::Test::TAG_SOURCE_FILE => "spec/models/user_spec.rb"}
  )
  2_000.times do |i|
    component.trace_test(
      "creates a user #{i}",
      suite_name,
      tags: {
        Datadog::CI::Ext::Test::TAG_FRAMEWORK => "rspec",
        Datadog::CI::Ext::Test::TAG_SOURCE_FILE => "spec/models/user_spec.rb",
        Datadog::CI::Ext::Test::TAG_SOURCE_START => "10",
        Datadog::CI::Ext::Test::TAG_SOURCE_END => "20"
      }
    ) do |test|
      test.passed!
      test.record_final_status
    end
  end
  suite_span.finish
end
