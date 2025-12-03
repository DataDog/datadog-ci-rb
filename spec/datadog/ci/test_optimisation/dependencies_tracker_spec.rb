# frozen_string_literal: true

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
        expect(tracker.bundle_location).to eq("vendor/bundle")
      end
    end

    context "when bundle_location is outside of the repo" do
      let(:bundle_location) { "/tmp/custom_bundle" }

      it "ignores the bundle location" do
        expect(tracker.bundle_location).to eq("")
      end
    end

    context "when bundle_location is nil" do
      it "keeps bundle_location empty" do
        expect(tracker.bundle_location).to eq("")
      end
    end
  end

  describe "#trackable_file?" do
    let(:bundle_location) { "/repo/project/bundle" }

    it "returns true for non-bundle paths" do
      expect(tracker.send(:trackable_file?, "lib/app.rb")).to be true
      expect(tracker.send(:trackable_file?, "spec/app_spec.rb")).to be true
      expect(tracker.send(:trackable_file?, "bundlelib/file.rb")).to be true
    end

    it "returns false when path is nil" do
      expect(tracker.send(:trackable_file?, nil)).to be false
    end

    it "returns false for empty paths" do
      expect(tracker.send(:trackable_file?, "")).to be false
    end

    it "returns false for files under the configured bundle location" do
      expect(tracker.send(:trackable_file?, "bundle/app.rb")).to be false
      expect(tracker.send(:trackable_file?, "bundle/lib/app.rb")).to be false
    end
  end
end
