# frozen_string_literal: true

require "tmpdir"

require_relative "../../../../lib/datadog/ci/test_optimization_cache/component"

RSpec.describe Datadog::CI::TestOptimizationCache::Component do
  let(:plan_folder) { Datadog::CI::Ext::TestOptimizationCache::PLAN_FOLDER }
  let(:manifest_path) { File.join(plan_folder, Datadog::CI::Ext::TestOptimizationCache::MANIFEST_FILE_NAME) }
  let(:http_cache_path) { Datadog::CI::Ext::TestOptimizationCache::TESTOPTIMIZATION_HTTP_CACHE_PATH }
  let(:legacy_cache_path) { Datadog::CI::Ext::TestOptimizationCache::TESTOPTIMIZATION_CACHE_PATH }
  let(:cache_settings) do
    {
      manifest_file: nil,
      runfiles_dir: nil,
      runfiles_manifest_file: nil,
      test_srcdir: nil
    }
  end
  let(:component) { described_class.new(**cache_settings) }

  around do |example|
    FileUtils.rm_rf(plan_folder)
    example.run
    FileUtils.rm_rf(plan_folder)
  end

  describe "#cache_available?" do
    it "returns false and does not load data when no manifest or legacy cache exists" do
      expect(component.cache_available?).to be false
      expect(component.load_settings).to be_nil
    end

    it "caches the selected reader" do
      FileUtils.mkdir_p(legacy_cache_path)
      File.write(
        File.join(legacy_cache_path, Datadog::CI::Ext::TestOptimizationCache::SETTINGS_FILE_NAME),
        JSON.generate("legacy" => true)
      )

      cached_component = component
      FileUtils.mkdir_p(http_cache_path)
      File.write(manifest_path, "1\n")
      File.write(
        File.join(http_cache_path, Datadog::CI::Ext::TestOptimizationCache::SETTINGS_FILE_NAME),
        JSON.generate("v1" => true)
      )

      expect(cached_component.load_settings).to eq("legacy" => true)
    end

    it "uses legacy cache when no manifest is present" do
      FileUtils.mkdir_p(legacy_cache_path)
      File.write(
        File.join(legacy_cache_path, Datadog::CI::Ext::TestOptimizationCache::SETTINGS_FILE_NAME),
        JSON.generate("legacy" => true)
      )

      expect(component.cache_available?).to be true
      expect(component.load_settings).to eq("legacy" => true)
    end

    it "uses manifest v1 cache and ignores legacy cache files" do
      FileUtils.mkdir_p(http_cache_path)
      FileUtils.mkdir_p(legacy_cache_path)
      File.write(manifest_path, "1\n")
      File.write(
        File.join(legacy_cache_path, Datadog::CI::Ext::TestOptimizationCache::SETTINGS_FILE_NAME),
        JSON.generate("legacy" => true)
      )
      File.write(
        File.join(http_cache_path, Datadog::CI::Ext::TestOptimizationCache::SETTINGS_FILE_NAME),
        JSON.generate("v1" => true)
      )

      expect(component.cache_available?).to be true
      expect(component.load_settings).to eq("v1" => true)
    end

    it "does not use manifest v1 cache when settings file is absent" do
      FileUtils.mkdir_p(legacy_cache_path)
      FileUtils.mkdir_p(File.dirname(manifest_path))
      File.write(manifest_path, "1\n")
      File.write(
        File.join(legacy_cache_path, Datadog::CI::Ext::TestOptimizationCache::SETTINGS_FILE_NAME),
        JSON.generate("legacy" => true)
      )

      expect(component.cache_available?).to be false
      expect(component.load_settings).to be_nil
    end

    it "does not fall back to legacy cache when manifest version is unsupported" do
      FileUtils.mkdir_p(legacy_cache_path)
      FileUtils.mkdir_p(File.dirname(manifest_path))
      File.write(manifest_path, "2\n")

      expect(component.cache_available?).to be false
      expect(component.load_settings).to be_nil
    end

    it "does not read global configuration" do
      expect(Datadog).not_to receive(:configuration)

      described_class.new(**cache_settings)
    end
  end
end
