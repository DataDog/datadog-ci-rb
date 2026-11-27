# frozen_string_literal: true

require "benchmark"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci/utils/test_name"

iterations = Integer(ENV.fetch("ITERATIONS", "100000"))

plain_samples = [
  "UserModelTest",
  "creates a user with valid attributes",
  "UsersController at ./spec/controllers/users_controller_spec.rb",
  "test_should_redirect_when_unauthenticated",
  "returns 200 OK for authorized requests"
].freeze

mixed_samples = [
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

plain_names = Array.new(iterations) { |index| plain_samples[index % plain_samples.length] }
mixed_names = Array.new(iterations) { |index| mixed_samples[index % mixed_samples.length] }

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "Test names: #{iterations}"
puts

allocations = {}

Benchmark.bm(32) do |benchmark|
  {
    "test_name.normalize plain suite" => plain_names,
    "test_name.normalize mixed suite" => mixed_names
  }.each do |label, names|
    GC.start
    alloc_before = GC.stat(:total_allocated_objects)

    benchmark.report(label) do
      normalized_count = 0

      names.each do |name|
        Datadog::CI::Utils::TestName.normalize(name)
        normalized_count += 1
      end

      raise "normalized #{normalized_count}, expected #{iterations}" unless normalized_count == iterations
    end

    allocations[label] = GC.stat(:total_allocated_objects) - alloc_before
  end
end

puts
allocations.each do |label, count|
  puts format("%-32s allocated objects: %d", label, count)
end
