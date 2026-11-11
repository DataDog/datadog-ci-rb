# frozen_string_literal: true

# Invoked by minitest_spec_discovery.py in a fresh process for every sample.
require "json"
require "logger"
require "fileutils"

library, mode, fixture_dir, result_path = ARGV
$LOAD_PATH.unshift(File.join(library, "lib"))
require "minitest/spec"
require "datadog/ci"

raise "Wrong library loaded" unless $LOADED_FEATURES.include?(File.join(library, "lib/datadog/ci.rb"))

Datadog.configure do |c|
  c.logger.instance = Logger.new(File::NULL)
  c.telemetry.enabled = false
  c.ci.enabled = true
  c.ci.agentless_mode_enabled = true
  c.api_key = "unused-benchmark-key"
  c.ci.discard_traces = true
  c.ci.itr_enabled = false
  c.ci.git_metadata_upload_enabled = false
  c.ci.retry_failed_tests_enabled = false
  c.ci.retry_new_tests_enabled = false
  c.ci.test_management_enabled = false
  c.ci.impacted_tests_detection_enabled = false
  c.ci.test_discovery_enabled = mode == "discovery"
  c.ci.test_discovery_output_path = File.expand_path("discovery.jsonl")
  c.ci.instrument :minitest
end

require File.join(fixture_dir, "support.rb")
expected = JSON.parse(File.read(File.join(fixture_dir, "counts.json")))
paths = Dir[File.join(fixture_dir, "*_test.rb")].sort
GC.start
before_allocations = GC.stat(:total_allocated_objects)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
paths.each { |path| require path }
defined_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
defined_allocations = GC.stat(:total_allocated_objects)
passed = Minitest.run(["--no-plugins", "--seed", "12345"])
finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
finished_allocations = GC.stat(:total_allocated_objects)

raise "Tests failed" unless passed
if mode == "discovery"
  raise "Discovery executed tests" unless BenchmarkFixtures.executions.zero?
  raise "Wrong discovery count" unless File.foreach("discovery.jsonl").count == expected.fetch("tests")
else
  raise "Wrong execution count" unless BenchmarkFixtures.executions == expected.fetch("tests")
end

captured = Minitest::Runnable.runnables.count { |klass| klass.respond_to?(:dd_spec_source_file) && klass.dd_spec_source_file }
File.write(result_path, JSON.generate(
  ruby: RUBY_DESCRIPTION,
  minitest: Minitest::VERSION,
  definition_seconds: defined_at - started,
  run_seconds: finished - defined_at,
  total_seconds: finished - started,
  definition_allocations: defined_allocations - before_allocations,
  total_allocations: finished_allocations - before_allocations,
  captured_specs: captured,
  tests: expected.fetch("tests"),
  classes: expected.fetch("classes")
))
