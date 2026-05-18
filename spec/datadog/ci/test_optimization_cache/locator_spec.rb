# frozen_string_literal: true

require "tmpdir"

require_relative "../../../../lib/datadog/ci/test_optimization_cache/locator"

RSpec.describe Datadog::CI::TestOptimizationCache::Locator do
  let(:plan_folder) { Datadog::CI::Ext::TestOptimizationCache::PLAN_FOLDER }
  let(:manifest_path) { File.join(plan_folder, Datadog::CI::Ext::TestOptimizationCache::MANIFEST_FILE_NAME) }
  let(:manifest_file) { nil }
  let(:runfiles_dir) { nil }
  let(:runfiles_manifest_file) { nil }
  let(:test_srcdir) { nil }
  let(:locator) do
    described_class.new(
      manifest_file: manifest_file,
      runfiles_dir: runfiles_dir,
      runfiles_manifest_file: runfiles_manifest_file,
      test_srcdir: test_srcdir
    )
  end

  around do |example|
    FileUtils.rm_rf(plan_folder)
    example.run
    FileUtils.rm_rf(plan_folder)
  end

  describe "#manifest_path" do
    it "finds a local manifest" do
      FileUtils.mkdir_p(File.dirname(manifest_path))
      File.write(manifest_path, "1")

      expect(locator.manifest_path).to eq(manifest_path)
    end

    it "prefers the local manifest over a configured Bazel runfile manifest" do
      Dir.mktmpdir do |runfiles_dir|
        FileUtils.mkdir_p(File.dirname(manifest_path))
        File.write(manifest_path, "1")

        runfile_path = "workspace/.testoptimization/manifest.txt"
        absolute_manifest_path = File.join(runfiles_dir, runfile_path)
        FileUtils.mkdir_p(File.dirname(absolute_manifest_path))
        File.write(absolute_manifest_path, "1")

        locator = described_class.new(
          manifest_file: runfile_path,
          runfiles_dir: runfiles_dir,
          runfiles_manifest_file: nil,
          test_srcdir: nil
        )

        expect(locator.manifest_path).to eq(manifest_path)
      end
    end

    it "resolves manifest paths through RUNFILES_DIR" do
      Dir.mktmpdir do |runfiles_dir|
        runfile_path = "workspace/.testoptimization/manifest.txt"
        absolute_manifest_path = File.join(runfiles_dir, runfile_path)
        FileUtils.mkdir_p(File.dirname(absolute_manifest_path))
        File.write(absolute_manifest_path, "1")

        locator = described_class.new(
          manifest_file: runfile_path,
          runfiles_dir: runfiles_dir,
          runfiles_manifest_file: nil,
          test_srcdir: nil
        )

        expect(locator.manifest_path).to eq(absolute_manifest_path)
      end
    end

    it "resolves manifest paths through RUNFILES_MANIFEST_FILE" do
      Dir.mktmpdir do |runfiles_dir|
        runfile_path = "workspace/.testoptimization/manifest.txt"
        absolute_manifest_path = File.join(runfiles_dir, "manifest.txt")
        runfiles_manifest_path = File.join(runfiles_dir, "MANIFEST")
        File.write(absolute_manifest_path, "1")
        File.write(runfiles_manifest_path, "#{runfile_path} #{absolute_manifest_path}\n")

        locator = described_class.new(
          manifest_file: runfile_path,
          runfiles_dir: nil,
          runfiles_manifest_file: runfiles_manifest_path,
          test_srcdir: nil
        )

        expect(locator.manifest_path).to eq(absolute_manifest_path)
      end
    end

    it "caches manifest lookup" do
      expect(locator.manifest_path).to be_nil

      FileUtils.mkdir_p(File.dirname(manifest_path))
      File.write(manifest_path, "1")

      expect(locator.manifest_path).to be_nil
    end

    it "does not read global configuration" do
      expect(Datadog).not_to receive(:configuration)

      locator.manifest_path
    end
  end

  describe "#manifest_version" do
    it "strips whitespace and BOM from the manifest" do
      Dir.mktmpdir do |tmpdir|
        path = File.join(tmpdir, "manifest.txt")
        File.write(path, "\uFEFF1\n")

        expect(locator.manifest_version(path)).to eq("1")
      end
    end

    it "caches manifest version reads" do
      Dir.mktmpdir do |tmpdir|
        path = File.join(tmpdir, "manifest.txt")
        File.write(path, "1\n")

        expect(locator.manifest_version(path)).to eq("1")

        File.write(path, "2\n")

        expect(locator.manifest_version(path)).to eq("1")
      end
    end
  end
end
