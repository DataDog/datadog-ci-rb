require "datadog/ci/codeowners/parser"

RSpec.describe Datadog::CI::Codeowners::Parser do
  subject { described_class.new(root_file_path) }
  let(:matcher) { subject.parse }
  let(:fixtures_location) { "spec/support/fixtures/codeowners" }

  describe "#parse" do
    context "when no codeowners file exists" do
      let(:root_file_path) { "#{fixtures_location}/no_codeowners" }

      it "returns a Matcher instance with empty set of rules" do
        expect(matcher.list_owners("foo/bar.rb")).to be_nil
      end
    end

    context "when a default codeowners file exists in the root directory" do
      let(:root_file_path) { "#{fixtures_location}/default-codeowners" }

      it "returns a Matcher instance with default codeowners file path" do
        expect(matcher.list_owners("foo/bar.rb")).to eq(["@default"])
      end
    end

    context "when a codeowners file exists in a .github subdirectory" do
      let(:root_file_path) { "#{fixtures_location}/github-codeowners" }

      it "returns a Matcher instance with github codeowners file path" do
        expect(matcher.list_owners("foo/bar.rb")).to eq(["@github"])
      end
    end

    context "when a codeowners file exists in a .gitlab subdirectory" do
      let(:root_file_path) { "#{fixtures_location}/gitlab-codeowners" }

      it "returns a Matcher instance with gitlab codeowners file path" do
        expect(matcher.list_owners("foo/bar.rb")).to eq(["@gitlab"])
      end
    end

    context "when a codeowners file exists in a docs subdirectory" do
      let(:root_file_path) { "#{fixtures_location}/docs-codeowners" }

      it "returns a Matcher instance with docs codeowners file path" do
        expect(matcher.list_owners("foo/bar.rb")).to eq(["@docs"])
      end
    end
  end
end
