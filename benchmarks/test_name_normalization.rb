# frozen_string_literal: true

require "benchmark"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci/utils/test_name"

iterations = Integer(ENV.fetch("ITERATIONS", "100000"))

samples = [
  "plain test name",
  "is expected to eq #<User:0x000000010 @id=1>",
  "is expected to eq User",
  "created at 2026-07-09 10:11:12 +0200",
  "expires on 2026-07-09",
  "is expected to eq 1..10",
  "is expected to eq [1, 2, 3]",
  "is expected to eq {:a=>1, :b=>2}",
  "feature flag [beta] is enabled",
  "renders {template}"
].freeze

names = Array.new(iterations) { |index| samples[index % samples.length] }

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "Test names: #{iterations}"
puts

Benchmark.bm(32) do |benchmark|
  GC.start

  benchmark.report("test_name.normalize mixed suite") do
    normalized_count = 0

    names.each do |name|
      Datadog::CI::Utils::TestName.normalize(name)
      normalized_count += 1
    end

    raise "normalized #{normalized_count}, expected #{iterations}" unless normalized_count == iterations
  end
end
