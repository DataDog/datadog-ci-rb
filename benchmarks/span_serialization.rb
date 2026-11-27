# frozen_string_literal: true

# Run from the repository root:
#   bundle exec ruby benchmarks/span_serialization.rb [samples=5]

require "msgpack"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci"
require "datadog/ci/test_tracing/serializers/test_v2"
require "datadog/ci/transport/event_platform_transport"

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

  puts format("%-42s median: %8.2f ms (min: %8.2f ms) | allocs: %10d", label, median_ms, min_ms, median_allocs)
end

spans = Array.new(5_000) do |i|
  span = Datadog::Tracing::Span.new(
    "rspec.test",
    id: 200_000 + i,
    trace_id: 100_000 + i,
    resource: "UserSpec.example #{i}",
    service: "benchmark-suite",
    type: Datadog::CI::Ext::AppTypes::TYPE_TEST,
    start_time: Time.now.utc,
    end_time: Time.now.utc + 0.005,
    status: 0
  )
  span.set_tags(
    Datadog::CI::Ext::Test::TAG_FRAMEWORK => "rspec",
    Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION => "3.13.0",
    Datadog::CI::Ext::Test::TAG_NAME => "example #{i}",
    Datadog::CI::Ext::Test::TAG_SUITE => "UserSpec at ./spec/models/user_spec.rb",
    Datadog::CI::Ext::Test::TAG_SOURCE_FILE => "spec/models/user_spec.rb",
    Datadog::CI::Ext::Test::TAG_SOURCE_START => "10",
    Datadog::CI::Ext::Test::TAG_SOURCE_END => "25",
    Datadog::CI::Ext::Test::TAG_STATUS => "pass",
    Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID => "100001",
    Datadog::CI::Ext::Test::TAG_TEST_MODULE_ID => "100002",
    Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID => "100003",
    Datadog::CI::Ext::Test::TAG_OS_PLATFORM => "darwin24",
    Datadog::CI::Ext::Test::TAG_OS_ARCHITECTURE => "arm64",
    Datadog::CI::Ext::Test::TAG_RUNTIME_NAME => "ruby",
    Datadog::CI::Ext::Test::TAG_RUNTIME_VERSION => RUBY_VERSION
  )
  span
end.freeze

trace = Datadog::Tracing::TraceSegment.new(spans, id: 100_000)

class BenchEventPlatformTransport < Datadog::CI::Transport::EventPlatformTransport
  def pack_for_bench(encoded_events)
    pack_events(encoded_events)
  end

  private

  def write_payload_header(packer)
    packer.write_map_header(2)
    packer.write("version")
    packer.write(1)
    packer.write("events")
  end
end

transport = BenchEventPlatformTransport.new(api: nil)

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}) | samples=#{samples}"
puts "-" * 98

measure("serializer TestV2 + pack_events (5k)", samples: samples) do
  encoded = spans.map do |span|
    serializer = Datadog::CI::TestTracing::Serializers::TestV2.new(
      trace,
      span,
      options: {itr_correlation_id: "corr-123"}
    )
    raise "invalid serializer" unless serializer.valid?

    Datadog::Core::Encoding::MsgpackEncoder.encode(serializer)
  end
  transport.pack_for_bench(encoded)
end
