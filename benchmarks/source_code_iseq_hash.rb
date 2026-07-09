# frozen_string_literal: true

require "benchmark"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog/ci/source_code/iseq_hash"

simple_proc = proc { 41 + 1 }
nested_proc = proc { [1, 2, 3, 4, 5].map { |value| value * 2 }.select(&:even?) }
rspec_like_proc = proc { expect(described_class.active).to eq(context) }

samples = {
  "simple proc" => simple_proc,
  "nested proc" => nested_proc,
  "rspec-like proc" => rspec_like_proc
}

iterations = Integer(ENV.fetch("ITERATIONS", "100000"))

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "Iterations: #{iterations}"
puts

Benchmark.bm(32) do |benchmark|
  samples.each do |label, target|
    benchmark.report("iseq_hash #{label}") do
      iterations.times do
        Datadog::CI::SourceCode.iseq_hash(target)
      end
    end

    benchmark.report("iseq.to_a #{label}") do
      iterations.times do
        RubyVM::InstructionSequence.of(target).to_a
      end
    end
  end
end
