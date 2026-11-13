# frozen_string_literal: true

# Run from the repository root:
#   bundle exec ruby benchmarks/test_impact_analysis_file_access.rb [tests=2000] [reads=5] [samples=5]
# Append a maximum overhead percentage to enforce a budget, e.g. 10000 5 7 10.
# Each sample uses a fresh process: prepended hooks cannot be removed safely.
# Measures the real RSpec runner with native TIA coverage and MessagePack encoding
# in both modes. Network requests are stubbed; dependency loading and fixture/test
# creation are excluded. This deliberately file-heavy suite is not a Rails forecast.

require "json"
require "open3"
require "rbconfig"

def run_worker(mode, tests, reads)
  require "rspec/core"
  require "rspec/mocks/standalone"
  require "csv"
  require "yaml"
  require "pathname"
  require "tmpdir"
  require "stringio"
  require "datadog/ci"

  settings = Datadog::CI::Remote::LibrarySettings.from_json(
    "itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false
  )
  allow_any_instance_of(Datadog::CI::Remote::LibrarySettingsClient).to receive(:fetch).and_return(settings)

  Datadog.configure do |config|
    config.telemetry.enabled = false
    config.diagnostics.startup_logs.enabled = false
    config.api_key = "local-benchmark"
    config.ci.enabled = true
    config.ci.agentless_mode_enabled = true
    config.ci.discard_traces = true
    config.ci.git_metadata_upload_enabled = false
    config.ci.itr_enabled = true
    config.ci.tia_opened_files_coverage_enabled = mode == "tracked"
    config.ci.instrument :rspec
  end

  component = Datadog.send(:components).test_impact_analysis
  events = 0
  dependencies = 0
  # Include serialization cost, without asynchronous network delivery or buffering.
  allow(component).to receive(:write) do |event|
    payload = MessagePack.unpack(MessagePack.pack(event))
    events += 1
    dependencies += payload.fetch("files").count { |file| file.fetch("filename").end_with?("/fixture.json") }
  end

  root = Datadog::CI::Git::LocalRepository.root
  Dir.mktmpdir("file-access-benchmark-", root) do |directory|
    File.write(File.join(directory, "fixture.json"), "42\n")
    readers = [
      -> { File.open("fixture.json").tap { |file| file.read }.close },
      -> { File.new("fixture.json").tap { |file| file.read }.close },
      -> { Kernel.open("fixture.json", &:read) },
      -> { File.read("fixture.json") },
      -> { File.binread("fixture.json") },
      -> { File.read(Pathname.new("fixture.json")) },
      -> { File.binread(Pathname.new("fixture.json")) },
      -> { Pathname.new("fixture.json").read },
      -> { CSV.read("fixture.json") },
      -> { YAML.load_file("fixture.json") },
      -> { JSON.parse(File.read("fixture.json")) }
    ]
    RSpec.describe "File readers" do
      tests.times do |index|
        reader = readers[index % readers.size]
        it("reads fixture #{index}") { reads.times { reader.call } }
      end
    end
    output = StringIO.new
    # Ignore repository .rspec/spec_helper: this is a standalone customer test run.
    options = RSpec::Core::ConfigurationOptions.new(["--options", File::NULL, "--pattern", "none", "--format", "progress"])
    runner = RSpec::Core::Runner.new(options)
    GC.start
    allocations = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status = Dir.chdir(directory) { runner.run(output, output) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocations = GC.stat(:total_allocated_objects) - allocations
    raise output.string unless status.zero?
    raise "Native TIA coverage is unavailable; run bundle exec rake compile_ext" unless component.code_coverage?
    raise "Expected #{tests} coverage events, got #{events}" unless events == tests
    expected = (mode == "tracked" && reads.positive?) ? tests : 0
    raise "Expected #{expected} fixture dependencies, got #{dependencies}" unless dependencies == expected

    puts JSON.generate(mode: mode, seconds: elapsed, allocations: allocations, tests: tests, reads: reads, events: events)
  end
ensure
  Datadog.shutdown! if defined?(Datadog)
end

if ARGV.first == "--worker"
  _, mode, tests, reads = ARGV
  run_worker(mode, Integer(tests), Integer(reads))
else
  tests, reads, samples = [Integer(ARGV.fetch(0, "2000")), Integer(ARGV.fetch(1, "5")), Integer(ARGV.fetch(2, "5"))]
  raise "tests/samples must be positive and reads nonnegative" unless tests.positive? && samples.positive? && reads >= 0
  maximum_overhead = Float(ARGV[3]) if ARGV[3]
  if maximum_overhead && (!maximum_overhead.finite? || maximum_overhead.negative?)
    raise "maximum overhead must be finite and nonnegative"
  end

  results = {"baseline" => [], "tracked" => []}
  samples.times do |sample|
    modes = sample.even? ? results.keys : results.keys.reverse
    modes.each do |mode|
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, __FILE__, "--worker", mode, tests.to_s, reads.to_s)
      raise "#{mode} failed: #{stderr}\n#{stdout}" unless status.success?
      result = JSON.parse(stdout)
      results.fetch(mode) << result.fetch("seconds")
      puts "Sample #{sample + 1}: #{stdout.strip}"
    end
  end
  medians = results.transform_values do |values|
    sorted = values.sort
    (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0
  end
  baseline, tracked = medians.values_at("baseline", "tracked")
  overhead = (tracked / baseline - 1) * 100
  puts "Ruby #{RUBY_VERSION}: #{tests} tests, #{reads} reads/test, #{samples} samples/mode"
  puts format("Median baseline %.4fs, tracked %.4fs: %+.2f%% (%+.2f us/test)",
    baseline, tracked, overhead, (tracked - baseline) / tests * 1_000_000)
  abort "Overhead exceeds #{maximum_overhead}% budget" if maximum_overhead && overhead > maximum_overhead
end
