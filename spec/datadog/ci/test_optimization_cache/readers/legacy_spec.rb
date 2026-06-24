# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/test_optimization_cache/readers/legacy"

RSpec.describe Datadog::CI::TestOptimizationCache::Readers::Legacy do
  let(:cache_path) { Datadog::CI::Ext::TestOptimizationCache::TESTOPTIMIZATION_CACHE_PATH }
  let(:reader) { described_class.new }

  around do |example|
    FileUtils.rm_rf(Datadog::CI::Ext::TestOptimizationCache::PLAN_FOLDER)
    example.run
    FileUtils.rm_rf(Datadog::CI::Ext::TestOptimizationCache::PLAN_FOLDER)
  end

  before do
    FileUtils.mkdir_p(cache_path)
  end

  it "is available" do
    expect(reader.available?).to be true
  end

  it "loads legacy settings without wrapping them" do
    payload = {"itr_enabled" => true}
    File.write(
      File.join(cache_path, Datadog::CI::Ext::TestOptimizationCache::SETTINGS_FILE_NAME),
      JSON.generate(payload)
    )

    expect(reader.load_settings).to eq(payload)
  end

  it "wraps legacy known tests in backend response shape" do
    payload = {"tests" => {"rspec" => {"suite" => ["test"]}}}
    File.write(
      File.join(cache_path, Datadog::CI::Ext::TestOptimizationCache::KNOWN_TESTS_FILE_NAME),
      JSON.generate(payload)
    )

    expect(reader.load_known_tests).to eq("data" => {"attributes" => payload})
  end

  it "wraps legacy test management tests in backend response shape" do
    payload = {"modules" => {"module" => {"suites" => {}}}}
    File.write(
      File.join(cache_path, Datadog::CI::Ext::TestOptimizationCache::LEGACY_TEST_MANAGEMENT_TESTS_FILE_NAME),
      JSON.generate(payload)
    )

    expect(reader.load_test_management).to eq("data" => {"attributes" => payload})
  end

  it "converts legacy skippable tests from the previous cache format" do
    payload = {
      "correlationId" => "legacy-correlation-id",
      "skippableTests" => {
        "suite" => {
          "test" => [
            {
              "suite" => "suite",
              "name" => "test",
              "parameters" => "{\"arguments\":{}}"
            }
          ]
        }
      }
    }
    File.write(
      File.join(cache_path, Datadog::CI::Ext::TestOptimizationCache::SKIPPABLE_TESTS_FILE_NAME),
      JSON.generate(payload)
    )

    expect(reader.load_skippable_tests).to eq(
      "meta" => {"correlation_id" => "legacy-correlation-id"},
      "data" => [
        {
          "type" => Datadog::CI::Ext::Test::DEFAULT_TIA_TEST_SKIPPING_MODE,
          "attributes" => {
            "suite" => "suite",
            "name" => "test",
            "parameters" => "{\"arguments\":{}}"
          }
        }
      ]
    )
  end

  it "treats nil legacy skippable tests as empty" do
    payload = {
      "correlationId" => "legacy-correlation-id",
      "skippableTests" => nil
    }
    File.write(
      File.join(cache_path, Datadog::CI::Ext::TestOptimizationCache::SKIPPABLE_TESTS_FILE_NAME),
      JSON.generate(payload)
    )

    expect(reader.load_skippable_tests).to eq(
      "meta" => {"correlation_id" => "legacy-correlation-id"},
      "data" => []
    )
  end
end
