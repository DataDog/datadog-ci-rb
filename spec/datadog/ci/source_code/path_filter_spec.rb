# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/source_code/path_filter"

RSpec.describe Datadog::CI::SourceCode::PathFilter do
  describe ".included?" do
    let(:root_path) { "/app/project" }
    let(:ignored_path) { nil }

    subject(:included?) { described_class.included?(path, root_path, ignored_path) }

    context "when path is under root_path" do
      let(:path) { "/app/project/lib/foo.rb" }

      it { is_expected.to be true }
    end

    context "when path equals root_path" do
      let(:path) { "/app/project" }

      it { is_expected.to be true }
    end

    context "when path is not under root_path" do
      let(:path) { "/other/path/foo.rb" }

      it { is_expected.to be false }
    end

    context "when path has similar prefix but is not under root_path" do
      let(:path) { "/app/project_other/foo.rb" }

      it "matches prefix (no trailing slash check)" do
        # This matches how the C implementation works (strncmp prefix)
        expect(included?).to be true
      end
    end

    context "with ignored_path" do
      let(:ignored_path) { "/app/project/vendor" }

      context "when path is under root_path but not ignored" do
        let(:path) { "/app/project/lib/foo.rb" }

        it { is_expected.to be true }
      end

      context "when path is under ignored_path" do
        let(:path) { "/app/project/vendor/bundle/foo.rb" }

        it { is_expected.to be false }
      end

      context "when path equals ignored_path" do
        let(:path) { "/app/project/vendor" }

        it { is_expected.to be false }
      end
    end

    context "with empty ignored_path" do
      let(:ignored_path) { "" }
      let(:path) { "/app/project/lib/foo.rb" }

      it "does not exclude any paths" do
        expect(included?).to be true
      end
    end

    context "with nil ignored_path" do
      let(:ignored_path) { nil }
      let(:path) { "/app/project/lib/foo.rb" }

      it "does not exclude any paths" do
        expect(included?).to be true
      end
    end

    context "with non-string path" do
      let(:path) { nil }

      it { is_expected.to be false }
    end

    context "with non-string root_path" do
      let(:root_path) { nil }
      let(:path) { "/app/project/foo.rb" }

      it { is_expected.to be false }
    end

    context "when ignored_path is not a string" do
      let(:ignored_path) { 123 }
      let(:path) { "/app/project/lib/foo.rb" }

      it "ignores non-string ignored_path" do
        expect(included?).to be true
      end
    end

    context "when both root_path and ignored_path are the same" do
      let(:root_path) { "/app/project" }
      let(:ignored_path) { "/app/project" }
      let(:path) { "/app/project/lib/foo.rb" }

      it "excludes all files" do
        expect(included?).to be false
      end
    end

    context "with trailing slashes" do
      context "when root_path has trailing slash" do
        let(:root_path) { "/app/project/" }
        let(:path) { "/app/project/lib/foo.rb" }

        it { is_expected.to be true }
      end

      context "when root_path has trailing slash and path does not start with it" do
        let(:root_path) { "/app/project/" }
        let(:path) { "/app/project_other/foo.rb" }

        it { is_expected.to be false }
      end
    end
  end
end
