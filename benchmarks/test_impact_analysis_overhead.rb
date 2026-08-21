# frozen_string_literal: true

# Models a high-cardinality TIA workload while keeping the expensive parts
# independently measurable:
#
# * 60,000 tests
# * 5,000 Ruby files covered across a suite
# * configurable fixture allocations in every covered file
# * thousands of custom impacted files, either registered once on the suite or
#   added at test level and rolled up by the suite
#
# Each workload dimension is independently configurable. The lifecycle
# defaults deliberately put all 5,000 files in one context coverage as a
# stress case. CONTEXT_DEPTH repeats that same file universe through nested
# contexts, exposing work hidden by the unique-file total. Set CONTEXT_FILES=0
# and sweep TESTS_PER_SUITE and the custom-file knobs to attribute costs.
#
# Lifecycle scenarios execute the production Component callbacks, AsyncWriter,
# coverage transport, and native serializer. The API sink records payload
# bytes without network I/O. The final signature check compares test-span and
# total overhead to show where each scenario attributes its work.
#
# The default run limits payload serialization to 1,000 events because 3,000
# custom files in 60,000 per-test payloads serializes 180 million file entries.
# Set PAYLOAD_EVENTS=60000 or run an end-to-end pipeline scenario when that
# exact cost is the subject of the profile.
#
# Compile the native extension first:
#
#   bundle exec rake compile_ext
#
# Run the default diagnostic matrix:
#
#   bundle exec ruby benchmarks/test_impact_analysis_overhead.rb
#
# Remove the context-coverage stress input:
#
#   CONTEXT_FILES=0 SCENARIOS=lifecycle_body,lifecycle_suite,lifecycle_test \
#     bundle exec ruby benchmarks/test_impact_analysis_overhead.rb
#
# Sweep the number of tests sharing each suite-level coverage payload:
#
#   TESTS_PER_SUITE=10 SCENARIOS=lifecycle_body,lifecycle_suite,lifecycle_test \
#     bundle exec ruby benchmarks/test_impact_analysis_overhead.rb
#
# Run a full-scale serialization scenario:
#
#   SCENARIOS=serialize_test_custom PAYLOAD_EVENTS=60000 \
#     bundle exec ruby benchmarks/test_impact_analysis_overhead.rb
#
# Compare custom files registered once on the suite with the same files added
# by every test:
#
#   CUSTOM_FILES=3000 TEST_CUSTOM_FILES=0 SCENARIOS=pipeline_test_alloc,pipeline_suite_alloc \
#     bundle exec ruby benchmarks/test_impact_analysis_overhead.rb
#   CUSTOM_FILES=0 TEST_CUSTOM_FILES=3000 SCENARIOS=pipeline_test_alloc,pipeline_suite_alloc \
#     bundle exec ruby benchmarks/test_impact_analysis_overhead.rb
#
# Exercise the worst credible amplification found in the production paths:
# test-level custom files roll up cumulatively in suite mode, nested contexts
# repeatedly merge overlapping hashes, and static dependencies repeatedly
# merge overlapping dependency hashes.
#
#   CUSTOM_FILES=0 TEST_CUSTOM_FILES=3000 TEST_CUSTOM_VARIANTS=10 \
#     CONTEXT_DEPTH=8 STATIC_DEPENDENCIES_PER_FILE=100 \
#     LIFECYCLE_TESTS=100 TESTS_PER_SUITE=100 \
#     SCENARIOS=lifecycle_body,lifecycle_suite,lifecycle_test \
#     bundle exec ruby benchmarks/test_impact_analysis_overhead.rb
#
# Give each suite a different deterministic randomized permutation of the
# 5,000-file universe, then partition that permutation across its tests. This
# preserves a 5,000-file suite union without repeating per-test coverage shapes:
#
#   COVERED_FILES=5000 FILES_PER_TEST=50 LIFECYCLE_TESTS=1000 \
#     TESTS_PER_SUITE=100 CONTEXT_FILES=0 CUSTOM_FILES=3000 TEST_CUSTOM_FILES=0 \
#     STATIC_DEPENDENCIES_PER_FILE=50 COVERAGE_SEED=12345 \
#     PROCESS_RELATIVE_PREFIX=components/application \
#     SCENARIOS=lifecycle_test,lifecycle_test_prefixed_custom,lifecycle_test_prefixed_absolute_custom \
#     bundle exec ruby benchmarks/test_impact_analysis_overhead.rb
#
# Compare MessagePack's native all-absolute path with its relative-path and
# late-fallback cases:
#
#   PAYLOAD_EVENTS=100 \
#     SCENARIOS=packer_fast_absolute,packer_fast_relative,packer_late_fallback \
#     bundle exec ruby benchmarks/test_impact_analysis_overhead.rb
#
# On macOS, collect a native sampling profile for one scenario:
#
#   SCENARIOS=native_suite_alloc SAMPLE_OUT=tmp/tia-suite.sample.txt \
#     SAMPLE_SECONDS=20 \
#     bundle exec ruby benchmarks/test_impact_analysis_overhead.rb

require "fileutils"
require "msgpack"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "datadog"
require "datadog/ci/async_writer"
require "datadog/ci/test_impact_analysis/component"
require "datadog/ci/test_impact_analysis/coverage/event"
require "datadog/ci/test_impact_analysis/coverage/transport"
require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

unless Datadog::CI::FileSerialization.respond_to?(:pack_files)
  raise "Native extension is stale; run `bundle exec rake compile_ext`"
end

module TestImpactAnalysisOverheadBenchmark
  ROOT = File.expand_path("..", __dir__)
  GENERATED_FILES_ROOT = File.join(ROOT, "benchmarks", "generated_tia_overhead")
  EMPTY_FILES = [].freeze
  EMPTY_STATIC_DEPENDENCIES = {}.freeze
  STATIC_DEPENDENCIES_THREAD_KEY = :tia_benchmark_static_dependencies
  RELATIVE_PATH_PREFIX_THREAD_KEY = :tia_benchmark_relative_path_prefix

  # Keeps synthetic dependency data inside the benchmark while executing the
  # production Component enrichment method unchanged.
  module SyntheticStaticDependencies
    def populate!(*args)
      return if Thread.current[STATIC_DEPENDENCIES_THREAD_KEY]

      super
    end

    def fetch_static_dependencies(file)
      dependencies = Thread.current[STATIC_DEPENDENCIES_THREAD_KEY]
      return super unless dependencies

      dependencies.fetch(file, EMPTY_STATIC_DEPENDENCIES)
    end
  end

  Datadog::CI::SourceCode::StaticDependencies.singleton_class.prepend(SyntheticStaticDependencies)

  # Lets the benchmark exercise a process running from a subdirectory without
  # changing the host process cwd. Coverage::Files snapshots the value before
  # handing an event to the asynchronous writer.
  module SyntheticRelativePathPrefix
    def relative_path_prefix
      Thread.current[RELATIVE_PATH_PREFIX_THREAD_KEY] || super
    end
  end

  Datadog::CI::Git::LocalRepository.singleton_class.prepend(SyntheticRelativePathPrefix)

  SCENARIOS = %w[
    lifecycle_body
    lifecycle_suite
    lifecycle_test
    lifecycle_test_absolute_custom
    lifecycle_test_prefixed_custom
    lifecycle_test_prefixed_absolute_custom
    lifecycle_test_no_context
    lifecycle_test_no_context_merge
    lifecycle_test_no_custom
    lifecycle_test_no_encoding
    lifecycle_test_no_writer
    lifecycle_test_no_alloc
    lifecycle_test_late_fallback
    packer_fast_absolute
    packer_fast_relative
    packer_fast_relative_prefixed
    packer_fast_absolute_prefixed
    packer_late_fallback
    packer_late_fallback_prefixed
    body
    native_suite_no_alloc
    native_suite_alloc
    native_test_no_alloc
    native_test_alloc
    custom_merge
    serialize_test_native
    serialize_test_custom
    serialize_suite_custom
    pipeline_test_alloc
    pipeline_suite_alloc
  ].freeze

  DEFAULT_SCENARIOS = %w[
    lifecycle_body
    lifecycle_suite
    lifecycle_test
    lifecycle_test_no_context
    lifecycle_test_no_context_merge
    lifecycle_test_no_custom
    lifecycle_test_no_encoding
    lifecycle_test_no_writer
    lifecycle_test_no_alloc
  ].freeze

  HELP = <<~TEXT
    Usage:
      bundle exec ruby benchmarks/test_impact_analysis_overhead.rb

    Workload environment variables:
      TESTS=60000                  tests executed by native scenarios
      COVERED_FILES=5000           distinct generated Ruby source paths
      FILES_PER_TEST=10            generated files executed by each test
      COVERAGE_SEED=12345          deterministic randomized suite permutations
      PROCESS_RELATIVE_PREFIX=components/application
                                   stable repository prefix when cwd is a subfolder
      FIXTURES_PER_FILE=5          fixture objects allocated in each file
      CUSTOM_FILES=3000            relative suite-level custom files inherited per test
      TEST_CUSTOM_FILES=0          additional relative custom files added by every test
      LIFECYCLE_TESTS=1000         tests executed by lifecycle scenarios
      TESTS_PER_SUITE=100          test spans inside each synthetic RSpec suite
      CONTEXT_FILES=5000           files covered by before(:context) fixtures per suite
      CONTEXT_DEPTH=1              nested contexts carrying overlapping coverage
      STATIC_DEPENDENCIES_PER_FILE=0 synthetic overlapping dependencies per covered file
      BODY_WAIT_US=250             compressed non-Ruby/IO time inside each test span
      TEST_CUSTOM_VARIANTS=1       distinct test-custom path sets reused cyclically
      CUSTOM_PATH_PADDING=0        extra bytes added to every custom path
      WRITER_BUFFER=10000          maximum queued events for the async encoder
      WRITER_INTERVAL_MS=3         compressed form of the production 3-second flush interval
      PAYLOAD_EVENTS=1000          events serialized by per-test scenarios
      SUITE_PAYLOAD_REPEATS=100     repetitions for the one-event suite payload
      PIPELINE_TESTS=1000           tests executed by end-to-end scenarios
      SCENARIOS=<comma-separated>   scenarios to run (default: diagnostic matrix)

    Scenarios:
      lifecycle_body                span/body baseline; fixture setup remains outside spans
      lifecycle_suite               production suite callbacks + async encoding
      lifecycle_test                production per-test callbacks + async encoding
      lifecycle_test_absolute_custom diagnostic control using equivalent absolute custom paths
      lifecycle_test_prefixed_custom process-relative custom paths from a repository subfolder
      lifecycle_test_prefixed_absolute_custom equivalent absolute-path control
      lifecycle_test_no_context     per-test mode without before(:context) coverage
      lifecycle_test_no_context_merge collect context fixtures but do not merge them into tests
      lifecycle_test_no_custom      per-test mode without custom impacted files
      lifecycle_test_no_encoding    enqueue events without a background encoder
      lifecycle_test_no_writer      construct events but do not enqueue them
      lifecycle_test_no_alloc       per-test mode with allocation tracing disabled
      lifecycle_test_late_fallback  unsupported final custom path forces Ruby repack

    MessagePack fast-path scenarios:
      packer_fast_absolute         native coverage + all-absolute custom paths
      packer_fast_relative         native coverage + repository-relative custom paths
      packer_fast_relative_prefixed native coverage + process-relative custom paths from a subfolder
      packer_fast_absolute_prefixed equivalent absolute-path control
      packer_late_fallback         unsupported final path repeats work in Ruby fallback
      packer_late_fallback_prefixed same fallback with a non-empty process-relative prefix

    Primitive scenarios:
      body                         workload without coverage
      native_suite_no_alloc        one collector lifecycle, allocation hook off
      native_suite_alloc           one collector lifecycle, allocation hook on
      native_test_no_alloc         one collector lifecycle per test, allocation hook off
      native_test_alloc            one collector lifecycle per test, allocation hook on
      custom_merge                 suite/test custom-file Array union only
      serialize_test_native        per-test payloads without custom files
      serialize_test_custom        per-test payloads with inherited custom files
      serialize_suite_custom       suite payload with all covered/custom files
      pipeline_test_alloc          body + per-test collector + custom merge + serialization
      pipeline_suite_alloc         body + suite collector + one custom payload

    macOS native profile:
      Select exactly one scenario and set SAMPLE_OUT and SAMPLE_SECONDS. The
      benchmark repeats that scenario for at least the sampling duration.
  TEXT

  class Configuration
    attr_reader :tests, :covered_files, :files_per_test, :fixtures_per_file,
      :custom_files, :test_custom_files, :payload_events,
      :suite_payload_repeats, :pipeline_tests, :scenarios, :sample_out,
      :sample_seconds, :lifecycle_tests, :tests_per_suite, :context_files,
      :context_depth, :static_dependencies_per_file, :body_wait_us,
      :test_custom_variants, :custom_path_padding, :writer_buffer,
      :writer_interval_ms, :coverage_seed, :process_relative_prefix

    def initialize(environment = ENV)
      @tests = read_integer(environment, "TESTS", 60_000, minimum: 1)
      @covered_files = read_integer(environment, "COVERED_FILES", 5_000, minimum: 1)
      @files_per_test = read_integer(environment, "FILES_PER_TEST", 10, minimum: 1)
      @coverage_seed = read_integer(environment, "COVERAGE_SEED", 12_345, minimum: 0)
      @process_relative_prefix = read_relative_path_prefix(
        environment.fetch("PROCESS_RELATIVE_PREFIX", "components/application")
      )
      @fixtures_per_file = read_integer(environment, "FIXTURES_PER_FILE", 5, minimum: 0)
      @custom_files = read_integer(environment, "CUSTOM_FILES", 3_000, minimum: 0)
      @test_custom_files = read_integer(environment, "TEST_CUSTOM_FILES", 0, minimum: 0)
      @lifecycle_tests = read_integer(environment, "LIFECYCLE_TESTS", 1_000, minimum: 1)
      @tests_per_suite = read_integer(environment, "TESTS_PER_SUITE", 100, minimum: 1)
      @context_files = read_integer(environment, "CONTEXT_FILES", 5_000, minimum: 0)
      @context_depth = read_integer(environment, "CONTEXT_DEPTH", 1, minimum: 1)
      @static_dependencies_per_file = read_integer(
        environment,
        "STATIC_DEPENDENCIES_PER_FILE",
        0,
        minimum: 0
      )
      @body_wait_us = read_integer(environment, "BODY_WAIT_US", 250, minimum: 0)
      @test_custom_variants = read_integer(environment, "TEST_CUSTOM_VARIANTS", 1, minimum: 1)
      @custom_path_padding = read_integer(environment, "CUSTOM_PATH_PADDING", 0, minimum: 0)
      @writer_buffer = read_integer(environment, "WRITER_BUFFER", 10_000, minimum: 1)
      @writer_interval_ms = read_integer(environment, "WRITER_INTERVAL_MS", 3, minimum: 1)
      @payload_events = read_integer(environment, "PAYLOAD_EVENTS", 1_000, minimum: 1)
      @suite_payload_repeats = read_integer(environment, "SUITE_PAYLOAD_REPEATS", 100, minimum: 1)
      @pipeline_tests = read_integer(environment, "PIPELINE_TESTS", 1_000, minimum: 1)
      @scenarios = read_scenarios(environment.fetch("SCENARIOS", DEFAULT_SCENARIOS.join(",")))
      @sample_out = environment["SAMPLE_OUT"]
      @sample_seconds = read_integer(environment, "SAMPLE_SECONDS", 20, minimum: 1)

      raise "FILES_PER_TEST must not exceed COVERED_FILES" if files_per_test > covered_files
      raise "CONTEXT_FILES must not exceed COVERED_FILES" if context_files > covered_files
      if static_dependencies_per_file > covered_files
        raise "STATIC_DEPENDENCIES_PER_FILE must not exceed COVERED_FILES"
      end
      unless (lifecycle_tests % tests_per_suite).zero?
        raise "LIFECYCLE_TESTS must be divisible by TESTS_PER_SUITE"
      end
      raise "PIPELINE_TESTS must not exceed TESTS" if pipeline_tests > tests
      if sample_out && scenarios.size != 1
        raise "SAMPLE_OUT requires exactly one selected scenario"
      end
      if scenarios.include?("lifecycle_test_late_fallback") && test_custom_files.zero?
        raise "lifecycle_test_late_fallback requires TEST_CUSTOM_FILES to be positive"
      end
    end

    def lifecycle_suites
      lifecycle_tests / tests_per_suite
    end

    private

    def read_integer(environment, name, default, minimum:)
      value = Integer(environment.fetch(name, default.to_s), 10)
      raise "#{name} must be at least #{minimum}" if value < minimum

      value
    rescue ArgumentError
      raise "#{name} must be an integer"
    end

    def read_scenarios(value)
      scenarios = value.split(",").map(&:strip).reject(&:empty?)
      invalid = scenarios - SCENARIOS
      raise "Unknown scenarios: #{invalid.join(", ")}" unless invalid.empty?
      raise "At least one scenario is required" if scenarios.empty?

      scenarios
    end

    def read_relative_path_prefix(value)
      components = value.split(File::SEPARATOR).reject(&:empty?)
      if value.start_with?(File::SEPARATOR) || components.any? { |component| [".", ".."].include?(component) }
        raise "PROCESS_RELATIVE_PREFIX must be a normalized relative path"
      end

      components.empty? ? "" : "#{components.join(File::SEPARATOR)}#{File::SEPARATOR}"
    end
  end

  class FixtureRecord
    attr_reader :id, :label, :payload

    def initialize(id, label, payload)
      @id = id
      @label = label
      @payload = payload
    end
  end

  class UnsupportedFastPathString < String
  end

  class Workload
    attr_reader :generated_files, :suite_custom_files, :static_dependencies_map

    def initialize(configuration)
      @configuration = configuration
      @generated_files = Array.new(configuration.covered_files) do |index|
        File.join(GENERATED_FILES_ROOT, format("covered_%05d.rb", index))
      end.freeze
      @programs = generated_files.map { |path| compile_program(path) }.freeze
      # Packer scenarios repeat one already-collected suite event to make the
      # native serializer long enough to profile. Build that input once so the
      # profile does not measure synthetic Hash construction on every repeat.
      @suite_coverage = generated_files.to_h { |path| [path, true] }.freeze
      padding = "x" * configuration.custom_path_padding
      @suite_custom_files = Array.new(configuration.custom_files) do |index|
        custom_path("suite", padding, index)
      end.freeze
      test_custom_files = Array.new(configuration.test_custom_files) do |index|
        custom_path("test", padding, index)
      end.freeze
      @test_custom_file_sets = Array.new(configuration.test_custom_variants) do |variant|
        if variant.zero?
          test_custom_files
        else
          test_custom_files.map { |path| "#{path}.variant-#{variant}" }.freeze
        end
      end.freeze
      @absolute_suite_custom_files = {}
      @absolute_test_custom_file_sets = {}
      absolute_suite_custom_files
      absolute_test_custom_files
      absolute_suite_custom_files(configuration.process_relative_prefix)
      absolute_test_custom_files(relative_path_prefix: configuration.process_relative_prefix)
      @late_fallback_test_custom_file_sets = @test_custom_file_sets.map do |files|
        next EMPTY_FILES if files.empty?

        fallback_files = files.dup
        fallback_files[-1] = UnsupportedFastPathString.new(fallback_files[-1])
        fallback_files.freeze
      end.freeze
      @static_dependencies_map = build_static_dependencies_map
    end

    def run_tests(tests = @configuration.tests)
      checksum = 0
      tests.times do |test_index|
        checksum ^= execute_test(test_index)
      end
      checksum
    end

    def execute_test(test_index)
      checksum = 0
      test_file_indexes(test_index).each_with_index do |file_index, offset|
        checksum ^= @programs[file_index].call(
          FixtureRecord,
          test_index + offset,
          @configuration.fixtures_per_file
        )
      end
      checksum
    end

    def execute_context(suite_index, files = @configuration.context_files)
      checksum = 0
      first_file = (suite_index * files) % @programs.size
      files.times do |offset|
        file_index = (first_file + offset) % @programs.size
        checksum ^= @programs[file_index].call(
          FixtureRecord,
          suite_index + offset,
          @configuration.fixtures_per_file
        )
      end
      checksum
    end

    def source_file(index)
      generated_files[index % generated_files.size].delete_prefix("#{ROOT}/")
    end

    def wait_in_test
      return if @configuration.body_wait_us.zero?

      sleep(@configuration.body_wait_us / 1_000_000.0)
    end

    def coverage_for_test(test_index)
      test_file_indexes(test_index).to_h { |file_index| [generated_files[file_index], true] }
    end

    def coverage_for_suite
      @suite_coverage
    end

    def merged_custom_files
      suite_custom_files | test_custom_files
    end

    def test_custom_files(test_index = 0)
      @test_custom_file_sets[test_index % @test_custom_file_sets.size]
    end

    def absolute_suite_custom_files(relative_path_prefix = "")
      @absolute_suite_custom_files[relative_path_prefix] ||= suite_custom_files.map do |path|
        File.join(ROOT, relative_path_prefix, path)
      end.freeze
    end

    def absolute_test_custom_files(test_index = 0, relative_path_prefix: "")
      file_sets = @absolute_test_custom_file_sets[relative_path_prefix] ||= @test_custom_file_sets.map do |files|
        files.map { |path| File.join(ROOT, relative_path_prefix, path) }.freeze
      end.freeze
      file_sets[test_index % file_sets.size]
    end

    def late_fallback_test_custom_files(test_index)
      @late_fallback_test_custom_file_sets[test_index % @late_fallback_test_custom_file_sets.size]
    end

    def absolute_custom_files(relative_path_prefix = "")
      absolute_suite_custom_files(relative_path_prefix) |
        absolute_test_custom_files(relative_path_prefix: relative_path_prefix)
    end

    def late_fallback_custom_files
      @late_fallback_custom_files ||= begin
        files = merged_custom_files.dup
        raise "packer_late_fallback requires at least one custom file" if files.empty?

        files[-1] = UnsupportedFastPathString.new(files[-1])
        files.freeze
      end
    end

    private

    def test_file_indexes(test_index)
      files_count = generated_files.size
      return [0] if files_count == 1

      suite_index = test_index / @configuration.tests_per_suite
      test_index_in_suite = test_index % @configuration.tests_per_suite
      random = Random.new(@configuration.coverage_seed + suite_index)
      first_file = random.rand(files_count)
      step = random.rand(1...files_count)
      step = (step + 1) % files_count until step.gcd(files_count) == 1
      first_sequence_index = test_index_in_suite * @configuration.files_per_test

      Array.new(@configuration.files_per_test) do |offset|
        (first_file + ((first_sequence_index + offset) * step)) % files_count
      end
    end

    def custom_path(scope, padding, index)
      components = ["custom", scope]
      components << padding unless padding.empty?
      components << format("impacted_%05d.rb", index)
      components.join("/")
    end

    def build_static_dependencies_map
      dependencies_per_file = @configuration.static_dependencies_per_file
      return {}.freeze if dependencies_per_file.zero?

      generated_files.each_with_index.to_h do |path, file_index|
        dependencies = Array.new(dependencies_per_file) do |offset|
          generated_files[(file_index + offset + 1) % generated_files.size]
        end
        [path, dependencies.to_h { |dependency| [dependency, true] }.freeze]
      end.freeze
    end

    def compile_program(path)
      source = <<~RUBY
        lambda do |fixture_class, seed, fixture_count|
          fixture_index = 0
          value = seed
          while fixture_index < fixture_count
            fixture = fixture_class.new(value, "fixture-\#{value}", [value, fixture_index])
            value = ((fixture.id * 1_664_525) ^ fixture.label.length ^ fixture.payload.length) & 0x7fffffff
            fixture_index += 1
          end
          value
        end
      RUBY

      RubyVM::InstructionSequence.compile(source, path, path).eval
    end
  end

  class RemoteConfiguration
    def itr_enabled?
      true
    end

    def code_coverage_enabled?
      true
    end

    def tests_skipping_enabled?
      false
    end
  end

  class BenchmarkSession
    def set_tag(*)
    end
  end

  class BenchmarkContext
    def incr_tests_skipped_by_tia_count
    end
  end

  class BenchmarkSuite
    attr_reader :id, :source_file

    def initialize(id, source_file, custom_impacted_files)
      @id = id
      @source_file = source_file
      @custom_impacted_files = custom_impacted_files.dup
    end

    def name
      "benchmark-suite-#{id}"
    end

    def get_tag(_tag)
      "1"
    end

    def should_skip?
      false
    end

    def skipped_by_test_impact_analysis?
      false
    end

    def add_impacted_files(file_paths)
      raise "suite custom impacted files are already locked" if @custom_impacted_files.frozen?

      @custom_impacted_files.concat(file_paths)
      nil
    end

    def lock_custom_impacted_files
      @custom_impacted_files = @custom_impacted_files.uniq.freeze unless @custom_impacted_files.frozen?
      @custom_impacted_files
    end
  end

  class BenchmarkTest
    attr_reader :id, :test_suite_id, :test_session_id, :source_file, :test_suite
    attr_accessor :context_ids

    def initialize(id, test_suite, source_file, context_ids)
      @id = id
      @test_suite = test_suite
      @test_suite_id = test_suite.id
      @test_session_id = 1
      @source_file = source_file
      @context_ids = context_ids
      @custom_impacted_files = []
      @inherited_custom_impacted_files = EMPTY_FILES
    end

    def name
      "benchmark-test-#{id}"
    end

    def get_tag(_tag)
      "rspec"
    end

    def skipped_by_test_impact_analysis?
      false
    end

    def skipped?
      false
    end

    def add_impacted_files(file_paths)
      @custom_impacted_files.concat(file_paths)
      nil
    end

    def inherit_impacted_files(file_paths)
      @inherited_custom_impacted_files = file_paths
      nil
    end

    def lock_custom_impacted_files
      return @custom_impacted_files if @custom_impacted_files.frozen?

      if @custom_impacted_files.empty? && @inherited_custom_impacted_files.frozen?
        @custom_impacted_files = @inherited_custom_impacted_files
        return @custom_impacted_files
      end

      @custom_impacted_files = (
        @inherited_custom_impacted_files | @custom_impacted_files
      ).freeze
    end
  end

  class BenchmarkResponse
    attr_reader :request_size

    def initialize(request_size)
      @request_size = request_size
    end

    def ok?
      true
    end

    def server_error?
      false
    end

    def request_compressed
      false
    end

    def duration_ms
      0.0
    end
  end

  class BenchmarkCoverageAPI
    attr_reader :output_bytes

    def initialize
      @output_bytes = 0
    end

    def citestcov_request(path:, payload:)
      @output_bytes += payload.bytesize
      BenchmarkResponse.new(payload.bytesize)
    end
  end

  class RecordingCoverageTransport < Datadog::CI::TestImpactAnalysis::Coverage::Transport
    attr_reader :encoded_events, :oversized_events, :max_batch_events,
      :encoding_seconds, :oversized_warning_bytes

    def initialize(api:)
      super
      @encoded_events = 0
      @oversized_events = 0
      @max_batch_events = 0
      @encoding_seconds = 0.0
      @oversized_warning_bytes = 0
    end

    def send_events(events)
      @max_batch_events = [@max_batch_events, events.size].max
      super
    end

    private

    def encode_events(events)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      encoded = super
      @encoded_events += encoded.size
      encoded
    ensure
      @encoding_seconds += Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    end

    # Production logs the entire inspected event and then the encoded payload.
    # Build the first warning and account for both byte strings, but suppress
    # terminal I/O so an adversarial benchmark remains usable.
    def event_too_large?(event, encoded_event)
      return false unless encoded_event.size > max_payload_size

      @oversized_events += 1
      warning = "Payload too large: '#{event.inspect}'"
      @oversized_warning_bytes += warning.bytesize + encoded_event.bytesize
      true
    end
  end

  class AsyncEncodingWriter
    def initialize(max_events, interval_seconds)
      @api = BenchmarkCoverageAPI.new
      @transport = RecordingCoverageTransport.new(api: @api)
      @writer = Datadog::CI::AsyncWriter.new(
        transport: @transport,
        options: {
          buffer_size: max_events,
          interval: interval_seconds,
          shutdown_timeout: 60
        }
      )
      @written_events = 0
      @stopped = false
    end

    def write(event)
      @written_events += 1
      @writer.write(event)
    end

    def stop
      return if @stopped

      @stopped = true
      @writer.stop
      nil
    end

    def output_bytes
      @api.output_bytes
    end

    def encoded_events
      @transport.encoded_events
    end

    def dropped_events
      @written_events - encoded_events
    end

    def encoding_seconds
      @transport.encoding_seconds
    end

    def max_batch_events
      @transport.max_batch_events
    end

    def oversized_events
      @transport.oversized_events
    end

    def oversized_warning_bytes
      @transport.oversized_warning_bytes
    end
  end

  class QueueOnlyWriter
    attr_reader :written_events

    def initialize
      @written_events = 0
    end

    def write(_event)
      @written_events += 1
      nil
    end

    def stop
    end

    def output_bytes
      0
    end

    def encoded_events
      0
    end

    def dropped_events
      0
    end

    def encoding_seconds
      0.0
    end

    def max_batch_events
      0
    end

    def oversized_events
      0
    end

    def oversized_warning_bytes
      0
    end
  end

  Outcome = Struct.new(
    :operations,
    :checksum,
    :output_bytes,
    :span_seconds,
    :finish_seconds,
    :encoded_events,
    :dropped_events,
    :encoding_seconds,
    :max_batch_events,
    :oversized_events,
    :oversized_warning_bytes
  )

  class Runner
    def initialize(configuration, workload)
      @configuration = configuration
      @workload = workload
    end

    def run(scenario)
      send(scenario)
    end

    def warmup_lifecycle
      context_files = [@configuration.context_files, 10].min
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::SUITE,
        context_files: context_files,
        lifecycle_suites: 1,
        tests_per_suite: 1
      )
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        context_files: context_files,
        lifecycle_suites: 1,
        tests_per_suite: 1
      )
    end

    private

    def lifecycle_body
      run_lifecycle(mode: nil)
    end

    def lifecycle_suite
      run_lifecycle(mode: Datadog::CI::Ext::Test::TIATestSkippingMode::SUITE)
    end

    def lifecycle_test
      run_lifecycle(mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST)
    end

    def lifecycle_test_absolute_custom
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        use_absolute_custom_files: true
      )
    end

    def lifecycle_test_prefixed_custom
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        relative_path_prefix: @configuration.process_relative_prefix
      )
    end

    def lifecycle_test_prefixed_absolute_custom
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        relative_path_prefix: @configuration.process_relative_prefix,
        use_absolute_custom_files: true
      )
    end

    def lifecycle_test_no_context
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        context_files: 0
      )
    end

    def lifecycle_test_no_context_merge
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        merge_context_coverage: false
      )
    end

    def lifecycle_test_no_custom
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        include_custom_files: false
      )
    end

    def lifecycle_test_no_writer
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        writer_mode: :none
      )
    end

    def lifecycle_test_no_encoding
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        writer_mode: :queue_only
      )
    end

    def lifecycle_test_no_alloc
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        use_allocation_tracing: false
      )
    end

    def lifecycle_test_late_fallback
      run_lifecycle(
        mode: Datadog::CI::Ext::Test::TIATestSkippingMode::TEST,
        use_late_fallback_custom_files: true
      )
    end

    def packer_fast_absolute
      with_relative_path_prefix("") do
        run_test_serialization(custom_files: @workload.absolute_custom_files, suite_coverage: true)
      end
    end

    def packer_fast_relative
      with_relative_path_prefix("") do
        run_test_serialization(custom_files: @workload.merged_custom_files, suite_coverage: true)
      end
    end

    def packer_fast_relative_prefixed
      with_relative_path_prefix(@configuration.process_relative_prefix) do
        run_test_serialization(custom_files: @workload.merged_custom_files, suite_coverage: true)
      end
    end

    def packer_fast_absolute_prefixed
      prefix = @configuration.process_relative_prefix
      with_relative_path_prefix(prefix) do
        run_test_serialization(
          custom_files: @workload.absolute_custom_files(prefix),
          suite_coverage: true
        )
      end
    end

    def packer_late_fallback
      run_test_serialization(custom_files: @workload.late_fallback_custom_files, suite_coverage: true)
    end

    def packer_late_fallback_prefixed
      with_relative_path_prefix(@configuration.process_relative_prefix) do
        run_test_serialization(
          custom_files: @workload.late_fallback_custom_files,
          suite_coverage: true
        )
      end
    end

    def body
      Outcome.new(@configuration.tests, @workload.run_tests, 0)
    end

    def native_suite_no_alloc
      run_native_suite(use_allocation_tracing: false)
    end

    def native_suite_alloc
      run_native_suite(use_allocation_tracing: true)
    end

    def native_test_no_alloc
      run_native_tests(use_allocation_tracing: false)
    end

    def native_test_alloc
      run_native_tests(use_allocation_tracing: true)
    end

    def custom_merge
      checksum = 0
      @configuration.tests.times do
        checksum += @workload.merged_custom_files.size
      end
      Outcome.new(@configuration.tests, checksum, 0)
    end

    def serialize_test_native
      run_test_serialization(custom_files: EMPTY_FILES)
    end

    def serialize_test_custom
      run_test_serialization(custom_files: @workload.merged_custom_files)
    end

    def serialize_suite_custom
      coverage = @workload.coverage_for_suite
      custom_files = @workload.merged_custom_files
      checksum = 0
      @configuration.suite_payload_repeats.times do |index|
        checksum += serialize_event(coverage, custom_files, index + 1, test_id: nil)
      end
      Outcome.new(@configuration.suite_payload_repeats, checksum, checksum)
    end

    def pipeline_test_alloc
      collector = build_collector(use_allocation_tracing: true)
      checksum = 0
      output_bytes = 0

      @configuration.pipeline_tests.times do |test_index|
        collector.start
        checksum ^= @workload.execute_test(test_index)
        coverage = collector.stop
        custom_files = @workload.merged_custom_files
        output_bytes += serialize_event(coverage, custom_files, test_index + 1, test_id: test_index + 1)
      end

      Outcome.new(@configuration.pipeline_tests, checksum, output_bytes)
    end

    def pipeline_suite_alloc
      collector = build_collector(use_allocation_tracing: true)
      collector.start
      checksum = 0
      custom_files = @workload.suite_custom_files.dup
      @configuration.pipeline_tests.times do |test_index|
        checksum ^= @workload.execute_test(test_index)
        custom_files.concat(@workload.test_custom_files)
      end
      coverage = collector.stop
      output_bytes = serialize_event(coverage, custom_files.uniq.freeze, 1, test_id: nil)
      Outcome.new(@configuration.pipeline_tests, checksum, output_bytes)
    end

    def run_native_suite(use_allocation_tracing:)
      collector = build_collector(use_allocation_tracing: use_allocation_tracing)
      collector.start
      checksum = @workload.run_tests
      coverage = collector.stop
      validate_suite_coverage(coverage)
      Outcome.new(@configuration.tests, checksum ^ coverage.size, 0)
    end

    def run_native_tests(use_allocation_tracing:)
      collector = build_collector(use_allocation_tracing: use_allocation_tracing)
      checksum = 0

      @configuration.tests.times do |test_index|
        collector.start
        checksum ^= @workload.execute_test(test_index)
        coverage = collector.stop
        validate_test_coverage(coverage) if test_index.zero?
        checksum ^= coverage.size
      end

      Outcome.new(@configuration.tests, checksum, 0)
    end

    def run_test_serialization(custom_files:, suite_coverage: false)
      checksum = 0
      @configuration.payload_events.times do |test_index|
        coverage = if suite_coverage
          @workload.coverage_for_suite
        else
          @workload.coverage_for_test(test_index)
        end
        checksum += serialize_event(coverage, custom_files, test_index + 1, test_id: test_index + 1)
      end
      Outcome.new(@configuration.payload_events, checksum, checksum)
    end

    def serialize_event(coverage, custom_files, sequence, test_id:)
      files = Datadog::CI::TestImpactAnalysis::Coverage::Files.new(coverage, custom_files)
      event = Datadog::CI::TestImpactAnalysis::Coverage::Event.new(
        test_id: test_id&.to_s,
        test_suite_id: sequence.to_s,
        test_session_id: "1",
        files: files
      )
      MessagePack.pack(event).bytesize
    end

    def build_collector(use_allocation_tracing:)
      Datadog::CI::TestImpactAnalysis::Coverage::DDCov.new(
        root: ROOT,
        ignored_path: nil,
        threading_mode: :multi,
        use_allocation_tracing: use_allocation_tracing
      )
    end

    def run_lifecycle(
      mode:,
      context_files: @configuration.context_files,
      merge_context_coverage: true,
      include_custom_files: true,
      writer_mode: :async,
      use_allocation_tracing: true,
      use_late_fallback_custom_files: false,
      use_absolute_custom_files: false,
      relative_path_prefix: "",
      lifecycle_suites: @configuration.lifecycle_suites,
      tests_per_suite: @configuration.tests_per_suite
    )
      previous_relative_path_prefix = Thread.current[RELATIVE_PATH_PREFIX_THREAD_KEY]
      Thread.current[RELATIVE_PATH_PREFIX_THREAD_KEY] = relative_path_prefix
      Thread.current[:dd_coverage_collector] = nil
      static_dependencies = @workload.static_dependencies_map
      unless static_dependencies.empty?
        Thread.current[STATIC_DEPENDENCIES_THREAD_KEY] = static_dependencies
      end
      writer = if mode && writer_mode == :async
        AsyncEncodingWriter.new(
          @configuration.writer_buffer,
          @configuration.writer_interval_ms / 1_000.0
        )
      elsif mode && writer_mode == :queue_only
        QueueOnlyWriter.new
      end
      if mode
        component = build_component(
          mode,
          writer,
          use_allocation_tracing,
          static_dependencies_tracking_enabled: !static_dependencies.empty?
        )
      end
      context = BenchmarkContext.new
      span_seconds = 0.0
      finish_seconds = 0.0
      checksum = 0
      test_index = 0
      suite_custom_files = if include_custom_files
        if use_absolute_custom_files
          @workload.absolute_suite_custom_files(relative_path_prefix)
        else
          @workload.suite_custom_files
        end
      else
        EMPTY_FILES
      end

      lifecycle_suites.times do |suite_index|
        suite = BenchmarkSuite.new(
          suite_index + 1,
          @workload.source_file(suite_index),
          suite_custom_files
        )
        component&.on_test_suite_started(suite)

        collected_context_ids = []
        unless context_files.zero?
          @configuration.context_depth.times do |depth|
            context_id = "benchmark-context-#{suite_index}-#{depth}"
            component&.on_test_context_started(context_id)
            checksum ^= @workload.execute_context(
              (suite_index * @configuration.context_depth) + depth,
              context_files
            )
            collected_context_ids << context_id
          end
        end
        context_ids = merge_context_coverage ? collected_context_ids.freeze : EMPTY_FILES

        tests_per_suite.times do
          test = BenchmarkTest.new(
            test_index + 1,
            suite,
            @workload.source_file(test_index),
            context_ids
          )
          span_started_at = monotonic_time
          component&.on_test_started(test)
          checksum ^= @workload.execute_test(test_index)
          @workload.wait_in_test
          if include_custom_files
            custom_files = if use_late_fallback_custom_files
              @workload.late_fallback_test_custom_files(test_index)
            elsif use_absolute_custom_files
              @workload.absolute_test_custom_files(
                test_index,
                relative_path_prefix: relative_path_prefix
              )
            else
              @workload.test_custom_files(test_index)
            end
            test.add_impacted_files(custom_files)
          end
          if component
            finish_started_at = monotonic_time
            component.on_test_finished(test, context)
            finished_at = monotonic_time
            finish_seconds += finished_at - finish_started_at
          else
            finished_at = monotonic_time
          end
          span_seconds += finished_at - span_started_at
          test_index += 1
        end

        component&.on_test_suite_finished(suite, context)
        collected_context_ids.each { |context_id| component&.clear_context_coverage(context_id) }
      end

      writer&.stop
      Outcome.new(
        lifecycle_suites * tests_per_suite,
        checksum,
        writer&.output_bytes || 0,
        span_seconds,
        finish_seconds,
        writer&.encoded_events || 0,
        writer&.dropped_events || 0,
        writer&.encoding_seconds || 0,
        writer&.max_batch_events || 0,
        writer&.oversized_events || 0,
        writer&.oversized_warning_bytes || 0
      )
    ensure
      writer&.stop
      Thread.current[:dd_coverage_collector] = nil
      Thread.current[STATIC_DEPENDENCIES_THREAD_KEY] = nil
      Thread.current[RELATIVE_PATH_PREFIX_THREAD_KEY] = previous_relative_path_prefix
    end

    def build_component(mode, writer, use_allocation_tracing, static_dependencies_tracking_enabled: false)
      component = Datadog::CI::TestImpactAnalysis::Component.new(
        dd_env: "benchmark",
        coverage_writer: writer,
        enabled: true,
        test_skipping_mode: mode,
        bundle_location: File.join(ROOT, "lib"),
        use_single_threaded_coverage: false,
        use_allocation_tracing: use_allocation_tracing,
        static_dependencies_tracking_enabled: static_dependencies_tracking_enabled
      )
      component.configure(RemoteConfiguration.new, BenchmarkSession.new)
      component
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def with_relative_path_prefix(relative_path_prefix)
      previous = Thread.current[RELATIVE_PATH_PREFIX_THREAD_KEY]
      Thread.current[RELATIVE_PATH_PREFIX_THREAD_KEY] = relative_path_prefix
      yield
    ensure
      Thread.current[RELATIVE_PATH_PREFIX_THREAD_KEY] = previous
    end

    def validate_suite_coverage(coverage)
      generated_count = coverage.each_key.count { |path| path.start_with?(GENERATED_FILES_ROOT) }
      return if generated_count == @configuration.covered_files

      raise "suite coverage recorded #{generated_count} generated files, expected #{@configuration.covered_files}"
    end

    def validate_test_coverage(coverage)
      generated_count = coverage.each_key.count { |path| path.start_with?(GENERATED_FILES_ROOT) }
      return if generated_count == @configuration.files_per_test

      raise "test coverage recorded #{generated_count} generated files, expected #{@configuration.files_per_test}"
    end
  end

  Measurement = Struct.new(
    :scenario,
    :wall_seconds,
    :cpu_seconds,
    :gc_seconds,
    :allocated_objects,
    :minor_gc_count,
    :major_gc_count,
    :operations,
    :checksum,
    :output_bytes,
    :span_seconds,
    :finish_seconds,
    :encoded_events,
    :dropped_events,
    :encoding_seconds,
    :max_batch_events,
    :oversized_events,
    :oversized_warning_bytes
  ) do
    def outside_span_seconds
      return if span_seconds.nil?

      wall_seconds - span_seconds
    end
  end

  class Measurer
    def measure(scenario)
      GC.start
      GC::Profiler.clear
      before_gc = GC.stat
      before_cpu = Process.times
      GC::Profiler.enable
      started_at = monotonic_time
      outcome = yield
      wall_seconds = monotonic_time - started_at
      after_cpu = Process.times
      after_gc = GC.stat
      gc_seconds = GC::Profiler.total_time
      GC::Profiler.disable

      Measurement.new(
        scenario,
        wall_seconds,
        (after_cpu.utime + after_cpu.stime) - (before_cpu.utime + before_cpu.stime),
        gc_seconds,
        after_gc.fetch(:total_allocated_objects) - before_gc.fetch(:total_allocated_objects),
        after_gc.fetch(:minor_gc_count) - before_gc.fetch(:minor_gc_count),
        after_gc.fetch(:major_gc_count) - before_gc.fetch(:major_gc_count),
        outcome.operations,
        outcome.checksum,
        outcome.output_bytes,
        outcome.span_seconds,
        outcome.finish_seconds,
        outcome.encoded_events,
        outcome.dropped_events,
        outcome.encoding_seconds,
        outcome.max_batch_events,
        outcome.oversized_events,
        outcome.oversized_warning_bytes
      )
    ensure
      GC::Profiler.disable
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  class MacOSSampler
    def initialize(output_path, seconds)
      @output_path = File.expand_path(output_path)
      @seconds = seconds
    end

    def profile
      raise "SAMPLE_OUT is supported only on macOS" unless RUBY_PLATFORM.include?("darwin")
      raise "/usr/bin/sample is unavailable" unless File.executable?("/usr/bin/sample")

      FileUtils.mkdir_p(File.dirname(@output_path))
      sample_pid = Process.spawn(
        "/usr/bin/sample",
        Process.pid.to_s,
        @seconds.to_s,
        "-file",
        @output_path,
        out: File::NULL,
        err: $stderr
      )
      sleep 0.5
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @seconds
      outcome = nil
      runs = 0
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        current = yield
        outcome = if outcome
          Outcome.new(
            outcome.operations + current.operations,
            outcome.checksum ^ current.checksum,
            outcome.output_bytes + current.output_bytes,
            add_optional(outcome.span_seconds, current.span_seconds),
            add_optional(outcome.finish_seconds, current.finish_seconds),
            add_optional(outcome.encoded_events, current.encoded_events),
            add_optional(outcome.dropped_events, current.dropped_events),
            add_optional(outcome.encoding_seconds, current.encoding_seconds),
            max_optional(outcome.max_batch_events, current.max_batch_events),
            add_optional(outcome.oversized_events, current.oversized_events),
            add_optional(outcome.oversized_warning_bytes, current.oversized_warning_bytes)
          )
        else
          current
        end
        runs += 1
      end
      _, sample_status = Process.wait2(sample_pid)
      sample_pid = nil
      unless sample_status.success? && File.file?(@output_path)
        raise "/usr/bin/sample failed to write #{@output_path}"
      end
      warn "Profiled #{runs} scenario run(s) into #{@output_path}"
      outcome
    ensure
      Process.kill("TERM", sample_pid) if sample_pid && process_running?(sample_pid)
      Process.wait(sample_pid) if sample_pid && process_running?(sample_pid)
    end

    private

    def add_optional(left, right)
      return if left.nil? && right.nil?

      left.to_f + right.to_f
    end

    def max_optional(left, right)
      return if left.nil? && right.nil?

      [left.to_i, right.to_i].max
    end

    def process_running?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end
  end

  class CLI
    def initialize(configuration)
      @configuration = configuration
    end

    def run
      # Component telemetry is lazily initialized and logs process
      # configuration once. Keep that unrelated one-time work out of the first
      # lifecycle scenario.
      Datadog.send(:components).telemetry
      print_configuration
      workload = Workload.new(@configuration)
      # Keep one-time repository discovery, serializer initialization, and the
      # first fixture-driven GC cycle out of the scenario measurements.
      Datadog::CI::Git::LocalRepository.root
      workload.run_tests([@configuration.tests, 100].min)
      MessagePack.pack("warmup")
      runner = Runner.new(@configuration, workload)
      if (@configuration.scenarios & SCENARIOS.grep(/^lifecycle_/)).any?
        runner.warmup_lifecycle
      end
      measurer = Measurer.new
      measurements = @configuration.scenarios.map do |scenario|
        measurement = if @configuration.sample_out
          sampler = MacOSSampler.new(@configuration.sample_out, @configuration.sample_seconds)
          measurer.measure(scenario) { sampler.profile { runner.run(scenario) } }
        else
          measurer.measure(scenario) { runner.run(scenario) }
        end
        print_measurement(measurement)
        measurement
      end
      print_attribution_signature(measurements)
      measurements
    end

    private

    def print_configuration
      puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Tests: #{@configuration.tests}"
      puts "Covered files per suite: #{@configuration.covered_files}"
      puts "Covered files per test: #{@configuration.files_per_test}"
      puts "Randomized suite coverage seed: #{@configuration.coverage_seed}"
      prefix = @configuration.process_relative_prefix
      puts "Process-relative subfolder prefix: #{prefix.empty? ? "(empty)" : prefix}"
      puts "Fixture allocations per covered file: #{@configuration.fixtures_per_file}"
      puts "Inherited relative suite custom files per test: #{@configuration.custom_files}"
      puts "Relative test-level custom files added per test: #{@configuration.test_custom_files}"
      puts "Lifecycle tests: #{@configuration.lifecycle_tests} (#{@configuration.tests_per_suite} per suite)"
      puts "Context fixture files per context: #{@configuration.context_files}"
      puts "Nested context depth: #{@configuration.context_depth}"
      puts "Synthetic static dependencies per covered file: #{@configuration.static_dependencies_per_file}"
      puts "Compressed body wait: #{@configuration.body_wait_us}us per test"
      puts "Test-custom path variants: #{@configuration.test_custom_variants}"
      puts "Custom path padding: #{@configuration.custom_path_padding} bytes"
      puts "Async writer buffer: #{@configuration.writer_buffer} events"
      puts "Compressed async writer interval: #{@configuration.writer_interval_ms}ms"
      puts "Per-test payload events: #{@configuration.payload_events}"
      puts "End-to-end pipeline tests: #{@configuration.pipeline_tests}"
      puts
      puts "scenario                        wall(s)    cpu(s)   total_us    span_us  outside_us  finish_us  encode_us  alloc/op     KB/op   warnKB     enc    drop   batch    over"
    end

    def print_measurement(measurement)
      puts format(
        "%-29s %9.3f %9.3f %10.3f %10s %11s %10s %10s %9.1f %9.2f %8.2f %7s %7s %7s %7s",
        measurement.scenario,
        measurement.wall_seconds,
        measurement.cpu_seconds,
        measurement.wall_seconds * 1_000_000 / measurement.operations,
        per_operation(measurement.span_seconds, measurement.operations),
        per_operation(measurement.outside_span_seconds, measurement.operations),
        per_operation(measurement.finish_seconds, measurement.operations),
        per_operation(measurement.encoding_seconds, measurement.operations),
        measurement.allocated_objects.to_f / measurement.operations,
        measurement.output_bytes.to_f / measurement.operations / 1024,
        measurement.oversized_warning_bytes.to_f / measurement.operations / 1024,
        measurement.encoded_events || "-",
        measurement.dropped_events || "-",
        measurement.max_batch_events || "-",
        measurement.oversized_events || "-"
      )
    end

    def per_operation(seconds, operations)
      return "-" if seconds.nil?

      format("%.3f", seconds * 1_000_000 / operations)
    end

    def print_attribution_signature(measurements)
      by_scenario = measurements.to_h { |measurement| [measurement.scenario, measurement] }
      body = by_scenario["lifecycle_body"]
      suite = by_scenario["lifecycle_suite"]
      test = by_scenario["lifecycle_test"]
      return unless body && suite && test

      suite_overhead = suite.wall_seconds - body.wall_seconds
      test_overhead = test.wall_seconds - body.wall_seconds
      puts
      puts "Attribution-signature check (must match before profiles are treated as explanatory):"
      puts format("  suite-mode test span / baseline: %.2fx", suite.span_seconds / body.span_seconds)
      puts format("  per-test test span / baseline:   %.2fx", test.span_seconds / body.span_seconds)
      puts format("  suite-mode total / baseline:     %.2fx", suite.wall_seconds / body.wall_seconds)
      puts format("  per-test total / baseline:       %.2fx", test.wall_seconds / body.wall_seconds)
      puts format(
        "  extra per-test span vs suite:    %+.3fus/test",
        (test.span_seconds - suite.span_seconds) * 1_000_000 / test.operations
      )
      puts format(
        "  suite outside-span vs per-test:  %+.3fus/test",
        (suite.outside_span_seconds - test.outside_span_seconds) * 1_000_000 / test.operations
      )
      puts format(
        "  per-test total vs suite:         %+.3fus/test",
        (test.wall_seconds - suite.wall_seconds) * 1_000_000 / test.operations
      )
      if suite_overhead.positive? && test_overhead.positive?
        puts format("  suite/per-test total overhead:   %.2fx", suite_overhead / test_overhead)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.include?("--help")
    puts TestImpactAnalysisOverheadBenchmark::HELP
    exit
  end

  configuration = TestImpactAnalysisOverheadBenchmark::Configuration.new
  TestImpactAnalysisOverheadBenchmark::CLI.new(configuration).run
end
