# frozen_string_literal: true

require "tmpdir"
require "fileutils"

require_relative "../../../../lib/datadog/ci/test_optimisation/dependencies_tracker"

RSpec.describe Datadog::CI::TestOptimisation::DependenciesTracker do
  subject(:tracker) { described_class.new(bundle_location: bundle_location) }

  let(:bundle_location) { nil }
  let(:root_path) { "/repo/project" }

  before do
    allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(root_path)
  end

  describe "#initialize" do
    context "when bundle_location is within the repo" do
      let(:bundle_location) { "/repo/project/vendor/bundle" }

      it "keeps the relative path" do
        expect(tracker.bundle_location).to eq("/repo/project/vendor/bundle")
      end
    end

    context "when bundle_location is outside of the repo" do
      let(:bundle_location) { "/tmp/custom_bundle" }

      it "ignores the bundle location" do
        expect(tracker.bundle_location).to eq("/tmp/custom_bundle")
      end
    end

    context "when bundle_location is nil" do
      it "keeps bundle_location nil" do
        expect(tracker.bundle_location).to eq(nil)
      end
    end
  end

  describe "#trackable_file?" do
    let(:bundle_location) { "/repo/project/bundle" }

    it "returns true for non-bundle paths" do
      expect(tracker.send(:trackable_file?, "/repo/project/lib/app.rb")).to be true
      expect(tracker.send(:trackable_file?, "/repo/project/spec/app_spec.rb")).to be true
      expect(tracker.send(:trackable_file?, "/repo/project/bundlelib/file.rb")).to be true
    end

    it "returns false when path is nil" do
      expect(tracker.send(:trackable_file?, nil)).to be false
    end

    it "returns false for empty paths" do
      expect(tracker.send(:trackable_file?, "")).to be false
    end

    it "returns false for files under the configured bundle location" do
      expect(tracker.send(:trackable_file?, "/repo/project/bundle")).to be false
      expect(tracker.send(:trackable_file?, "/repo/project/bundle/app.rb")).to be false
      expect(tracker.send(:trackable_file?, "/repo/project/bundle/lib/app.rb")).to be false
    end
  end

  describe "#load" do
    let(:tmp_root) { Dir.mktmpdir }
    let(:root_path) { tmp_root }
    let(:bundle_location) { File.join(root_path, "bundle") }

    before do
      File.write(File.join(tmp_root, "app.rb"), "module App; end\n")
      FileUtils.mkdir_p(File.join(tmp_root, "bundle"))
      File.write(File.join(tmp_root, "bundle", "ignored.rb"), "module Ignored; end\n")
    end

    after do
      FileUtils.remove_entry(tmp_root)
    end

    it "parses Ruby files under the repository root without raising errors" do
      expect { tracker.load }.not_to raise_error
    end
  end
end
