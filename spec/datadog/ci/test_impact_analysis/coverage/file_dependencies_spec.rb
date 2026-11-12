# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../../../../support/file_dependency_stress"
require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/file_dependencies"

native_available = RUBY_ENGINE == "ruby" && !Gem.win_platform?
require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}" if native_available

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::FileDependencies do
  let(:directory) { Dir.mktmpdir("file-dependency-resolver-") }
  let(:root) { File.join(directory, "repository") }
  let(:ignored) { File.join(root, "vendor") }
  let(:resolver) { described_class.new(root: root, ignored_path: ignored) }

  before do
    FileUtils.mkdir_p(File.join(root, "nested", "child"))
    FileUtils.mkdir_p(ignored)
    ["input.json", "~literal.json", "caf\u00e9.json"].each { |name| File.write(File.join(root, name), "data") }
    File.write(File.join(root, "nested", "input.json"), "nested")
    File.write(File.join(ignored, "input.json"), "ignored")
    File.write(File.join(directory, "outside.json"), "outside")
    File.link(File.join(root, "input.json"), File.join(root, "hardlink.json"))
    File.symlink("hardlink.json", File.join(root, "alias.json"))
    File.symlink("nested/child", File.join(root, "directory_alias"))
    File.symlink("vendor/input.json", File.join(root, "ignored_alias.json"))
    File.symlink("missing-target.json", File.join(root, "dangling.json"))
    File.symlink("repository/input.json", File.join(directory, "outside_alias.json"))
  end

  after { FileUtils.remove_entry(directory) }

  def expected_paths(path)
    paths = [File.absolute_path(path)]
    begin
      paths << File.realpath(path)
    rescue SystemCallError
      nil
    end
    paths.uniq.select { |file| file.start_with?(root + "/") && !file.start_with?(ignored + "/") }
  end

  shared_examples "Ruby-compatible dependency paths" do
    it "collects paths from files opened with deep, long, and unusual valid names" do
      paths = FileDependencyStress.build(root)
      Dir.chdir(root) do
        inputs = paths + paths.map { |path| "./" + path.delete_prefix(root + "/") }
        inputs.each do |path|
          expected = expected_paths(path)
          File.open(path, "rb") do |file|
            expect(file.read).to eq(FileDependencyStress::CONTENTS)
            expect(resolver.paths_for(file)).to eq(expected)
          end
        end
      end
    end

    [
      "input.json", "./input.json", "nested/../input.json", "nested//input.json",
      "~literal.json", "caf\u00e9.json", "alias.json", "directory_alias/../input.json",
      "ignored_alias.json", "dangling.json", "missing.json", "../outside.json", "../outside_alias.json"
    ].each do |path|
      it "matches Ruby normalization and symlink resolution for #{path}" do
        Dir.chdir(root) do
          expect(resolver.paths_for(path)).to eq(expected_paths(path))
          absolute = root + "/" + path
          expect(resolver.paths_for(absolute)).to eq(expected_paths(absolute))
        end
      end
    end
  end

  context "with the native resolver", skip: !native_available do
    before { expect(resolver.respond_to?(:native_paths, true)).to be(true) }

    include_examples "Ruby-compatible dependency paths"

    it "declines an empty repository prefix safely" do
      expect(resolver.send(:native_paths, "input.json", "", nil)).to be_nil
    end

    it "keeps path arguments valid while other threads compact the heap" do
      path = File.join(root, "nested", "input.json")
      expected = [path]
      workers = Array.new(3) { Thread.new { 100.times { expect(resolver.paths_for(path)).to eq(expected) } } }
      3.times { GC.compact } if GC.respond_to?(:compact)
      workers.each(&:value)
    end
  end

  context "with the Ruby fallback" do
    before do
      allow(resolver).to receive(:native_paths).and_return(nil) if native_available
    end

    include_examples "Ruby-compatible dependency paths"
  end
end
