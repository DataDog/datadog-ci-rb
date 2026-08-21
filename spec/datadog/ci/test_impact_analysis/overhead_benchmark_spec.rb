# frozen_string_literal: true

require_relative "../../../../benchmarks/test_impact_analysis_overhead"

RSpec.describe TestImpactAnalysisOverheadBenchmark do
  let(:environment) do
    {
      "TESTS" => "4",
      "COVERED_FILES" => "4",
      "FILES_PER_TEST" => "2",
      "FIXTURES_PER_FILE" => "1",
      "CUSTOM_FILES" => "3",
      "TEST_CUSTOM_FILES" => "1",
      "LIFECYCLE_TESTS" => "4",
      "TESTS_PER_SUITE" => "2",
      "CONTEXT_FILES" => "4",
      "BODY_WAIT_US" => "0",
      "WRITER_BUFFER" => "10",
      "WRITER_INTERVAL_MS" => "1",
      "PAYLOAD_EVENTS" => "2",
      "SUITE_PAYLOAD_REPEATS" => "1",
      "PIPELINE_TESTS" => "2",
      "SCENARIOS" => "body"
    }
  end
  let(:configuration) { described_class::Configuration.new(environment) }
  let(:workload) { described_class::Workload.new(configuration) }
  let(:runner) { described_class::Runner.new(configuration, workload) }

  it "executes generated files under native suite coverage" do
    outcome = runner.run("native_suite_alloc")

    expect(outcome.operations).to eq(4)
  end

  it "executes generated files under per-test native coverage" do
    outcome = runner.run("native_test_no_alloc")

    expect(outcome.operations).to eq(4)
  end

  it "serializes inherited custom files in per-test payloads" do
    without_custom = runner.run("serialize_test_native")
    with_custom = runner.run("serialize_test_custom")

    expect(with_custom.checksum).to be > without_custom.checksum
  end

  it "runs both end-to-end attribution modes" do
    test_mode = runner.run("pipeline_test_alloc")
    suite_mode = runner.run("pipeline_suite_alloc")

    expect(test_mode.operations).to eq(2)
    expect(suite_mode.operations).to eq(2)
  end

  it "measures production callback work inside the test-span boundary" do
    suite_mode = runner.run("lifecycle_suite")
    test_mode = runner.run("lifecycle_test")

    expect(suite_mode.operations).to eq(4)
    expect(suite_mode.encoded_events).to eq(2)
    expect(test_mode.encoded_events).to eq(4)
    expect(test_mode.span_seconds).to be_positive
    expect(test_mode.finish_seconds).to be_positive
  end

  it "reports time outside test spans separately" do
    measurement = described_class::Measurer.new.measure("lifecycle_body") do
      runner.run("lifecycle_body")
    end

    expect(measurement.outside_span_seconds).to be >= 0
  end

  it "runs nested context and static-dependency amplification through the production component" do
    amplified_configuration = described_class::Configuration.new(
      environment.merge(
        "CONTEXT_DEPTH" => "2",
        "STATIC_DEPENDENCIES_PER_FILE" => "2",
        "TEST_CUSTOM_VARIANTS" => "2",
        "SCENARIOS" => "lifecycle_test"
      )
    )
    amplified_runner = described_class::Runner.new(
      amplified_configuration,
      described_class::Workload.new(amplified_configuration)
    )

    outcome = amplified_runner.run("lifecycle_test")

    expect(outcome.operations).to eq(4)
    expect(outcome.encoded_events).to eq(4)
  end

  it "exercises all MessagePack fast-path branches" do
    absolute = runner.run("packer_fast_absolute")
    relative = runner.run("packer_fast_relative")
    fallback = runner.run("packer_late_fallback")

    expect(absolute.operations).to eq(2)
    expect(relative.checksum).to eq(absolute.checksum)
    expect(fallback.checksum).to eq(relative.checksum)
  end

  it "forces late MessagePack fallback through the asynchronous lifecycle" do
    outcome = runner.run("lifecycle_test_late_fallback")

    expect(outcome.encoded_events).to eq(4)
    expect(outcome.encoding_seconds).to be_positive
  end

  it "rejects unknown scenarios" do
    expect do
      described_class::Configuration.new("SCENARIOS" => "unknown")
    end.to raise_error(RuntimeError, "Unknown scenarios: unknown")
  end
end
