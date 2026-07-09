# frozen_string_literal: true

require "benchmark"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci/contrib/rspec/anonymous_example_name"

samples = {
  "expect eq context" => proc { proc { expect(described_class.active).to eq(context) } },
  "is_expected be_empty" => proc { proc { is_expected.to be_empty } },
  "should eq array" => proc { proc { should eq([]) } },
  "change by" => proc { proc { expect { 1 + 1 }.to change { 2 + 2 }.by(0) } },
  "generic fallback" => proc { proc { 1 + 1 } }
}

iterations = Integer(ENV.fetch("ITERATIONS", "100000"))

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "New anonymous examples per sample: #{iterations}"
puts

Benchmark.bm(32) do |benchmark|
  factories = samples.values
  mixed_targets = Array.new(iterations) { |index| factories[index % factories.length].call }
  GC.start

  benchmark.report("anonymous_name mixed suite") do
    rendered_count = 0

    mixed_targets.each do |target|
      Datadog::CI::Contrib::RSpec::AnonymousExampleName.call(target) || "anonymous example"
      rendered_count += 1
    end

    raise "rendered #{rendered_count}, expected #{iterations}" unless rendered_count == iterations
  end

  samples.each do |label, factory|
    targets = Array.new(iterations) { factory.call }
    GC.start

    benchmark.report("anonymous_name #{label}") do
      rendered_count = 0

      targets.each do |target|
        Datadog::CI::Contrib::RSpec::AnonymousExampleName.call(target) || "anonymous example"
        rendered_count += 1
      end

      raise "rendered #{rendered_count}, expected #{iterations}" unless rendered_count == iterations
    end
  end
end
