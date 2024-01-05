require "datadog/ci/codeowners/matcher"

RSpec.describe Datadog::CI::Codeowners::Matcher do
  let(:codeowners_file_path) { "/path/to/codeowners" }
  let(:matcher) { described_class.new(codeowners_file_path) }

  before do
    allow(File).to receive(:exist?).with(codeowners_file_path).and_return(true)
    allow(File).to receive(:open).with(codeowners_file_path, "r").and_yield(StringIO.new(codeowners_content))
  end

  describe "#list_owners" do
    context "when the codeowners file is empty" do
      let(:codeowners_content) { "" }

      it "returns an empty array" do
        expect(matcher.list_owners("file.rb")).to eq([])
      end
    end

    context "when the codeowners file contains matching patterns" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          # Comment line
          /path/to/*.rb @owner3
          /path/to/file.rb @owner1 @owner2
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("/path/to/file.rb")).to eq(["@owner1", "@owner2"])
        expect(matcher.list_owners("/path/to/another_file.rb")).to eq(["@owner3"])
      end
    end

    context "when the codeowners file contains non-matching patterns" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          /path/to/file.rb @owner1
        CODEOWNERS
      end

      it "returns an empty array" do
        expect(matcher.list_owners("/path/to/another_file.rb")).to eq([])
      end
    end

    context "when the codeowners file contains comments and empty lines" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          # Comment line
          /path/to/*.rb @owner2

          # Another comment line
          /path/to/file.rb @owner1
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("/path/to/file.rb")).to eq(["@owner1"])
        expect(matcher.list_owners("/path/to/another_file.rb")).to eq(["@owner2"])
      end
    end

    context "when the codeowners file contains section lines" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          [section1]
          /path/to/*.rb @owner2

          [section2]
          /path/to/file.rb @owner1
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("/path/to/file.rb")).to eq(["@owner1"])
        expect(matcher.list_owners("/path/to/another_file.rb")).to eq(["@owner2"])
      end
    end
  end
end
