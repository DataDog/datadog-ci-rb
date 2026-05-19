# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/test_optimization_cache/readers/v1"

RSpec.describe Datadog::CI::TestOptimizationCache::Readers::V1 do
  let(:plan_folder) { Datadog::CI::Ext::TestOptimizationCache::PLAN_FOLDER }
  let(:http_cache_path) { Datadog::CI::Ext::TestOptimizationCache::TESTOPTIMIZATION_HTTP_CACHE_PATH }
  let(:reader) { described_class.new(plan_folder) }

  around do |example|
    FileUtils.rm_rf(plan_folder)
    example.run
    FileUtils.rm_rf(plan_folder)
  end

  it "is available" do
    FileUtils.mkdir_p(http_cache_path)
    File.write(
      File.join(http_cache_path, Datadog::CI::Ext::TestOptimizationCache::SETTINGS_FILE_NAME),
      JSON.generate(
        "data" => {
          "attributes" => {}
        }
      )
    )

    expect(reader.available?).to be true
  end

  it "is not available when settings response is absent" do
    expect(reader.available?).to be false
  end

  it "returns nil when settings response is absent" do
    expect(reader.load_settings).to be_nil
  end

  it "returns nil when optional responses are absent" do
    expect(reader.load_known_tests).to be_nil
    expect(reader.load_test_management).to be_nil
    expect(reader.load_skippable_tests).to be_nil
  end

  it "returns nil when an endpoint response contains invalid JSON" do
    FileUtils.mkdir_p(http_cache_path)
    File.write(
      File.join(http_cache_path, Datadog::CI::Ext::TestOptimizationCache::SETTINGS_FILE_NAME),
      "{"
    )

    expect(reader.load_settings).to be_nil
  end

  it "loads test management data from the manifest v1 file name" do
    FileUtils.mkdir_p(http_cache_path)
    payload = {
      "data" => {
        "attributes" => {
          "modules" => {}
        }
      }
    }
    File.write(
      File.join(http_cache_path, Datadog::CI::Ext::TestOptimizationCache::TEST_MANAGEMENT_FILE_NAME),
      JSON.generate(payload)
    )

    expect(reader.load_test_management).to eq(payload)
  end
end
