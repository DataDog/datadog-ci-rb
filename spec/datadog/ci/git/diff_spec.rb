# frozen_string_literal: true

require "datadog/ci/git/diff"
require "set"

RSpec.describe Datadog::CI::Git::Diff do
  describe "#initialize" do
    it "creates a diff with empty set by default" do
      diff = described_class.new
      expect(diff.to_set).to eq(Set.new)
    end

    it "creates a diff with provided changed files" do
      files = Set.new(["file1.rb", "file2.rb"])
      diff = described_class.new(changed_files: files)
      expect(diff.to_set).to eq(files)
    end
  end

  describe "#include?" do
    let(:files) { Set.new(["app/models/user.rb", "spec/models/user_spec.rb"]) }
    let(:diff) { described_class.new(changed_files: files) }

    it "returns true for files that are in the diff" do
      expect(diff.include?("app/models/user.rb")).to be true
      expect(diff.include?("spec/models/user_spec.rb")).to be true
    end

    it "returns false for files that are not in the diff" do
      expect(diff.include?("app/models/post.rb")).to be false
      expect(diff.include?("non_existent.rb")).to be false
    end
  end

  describe "#size" do
    it "returns the number of changed files" do
      files = Set.new(["file1.rb", "file2.rb", "file3.rb"])
      diff = described_class.new(changed_files: files)
      expect(diff.size).to eq(3)
    end

    it "returns 0 for empty diff" do
      diff = described_class.new
      expect(diff.size).to eq(0)
    end
  end

  describe "#empty?" do
    it "returns true for empty diff" do
      diff = described_class.new
      expect(diff.empty?).to be true
    end

    it "returns false for non-empty diff" do
      files = Set.new(["file1.rb", "file2.rb"])
      diff = described_class.new(changed_files: files)
      expect(diff.empty?).to be false
    end
  end

  describe "#inspect" do
    it "returns the inspect output of the underlying set" do
      files = Set.new(["file1.rb", "file2.rb"])
      diff = described_class.new(changed_files: files)
      expect(diff.inspect).to eq(files.inspect)
    end
  end

  describe ".parse_diff_output" do
    it "returns empty diff for nil output" do
      diff = described_class.parse_diff_output(nil)
      expect(diff.to_set).to eq(Set.new)
    end

    it "returns empty diff for empty output" do
      diff = described_class.parse_diff_output("")
      expect(diff.to_set).to eq(Set.new)
    end

    it "parses git diff output and extracts changed files" do
      git_output = <<~OUTPUT
        diff --git a/app/models/user.rb b/app/models/user.rb
        index 1234567..abcdefg 100644
        --- a/app/models/user.rb
        +++ b/app/models/user.rb
        @@ -1,3 +1,4 @@
         class User
        +  attr_accessor :name
         end
        diff --git a/spec/models/user_spec.rb b/spec/models/user_spec.rb
        index 7890123..xyz9876 100644
        --- a/spec/models/user_spec.rb
        +++ b/spec/models/user_spec.rb
        @@ -1,3 +1,6 @@
         RSpec.describe User do
        +  it "has a name" do
        +    expect(User.new.name).to be_nil
        +  end
         end
      OUTPUT

      # Mock relative_to_root to return the file paths as-is
      allow(Datadog::CI::Git::LocalRepository).to receive(:relative_to_root) do |path|
        path
      end

      diff = described_class.parse_diff_output(git_output)
      expected_files = Set.new(["app/models/user.rb", "spec/models/user_spec.rb"])
      expect(diff.to_set).to eq(expected_files)
    end

    it "handles files that get filtered out by relative_to_root" do
      git_output = <<~OUTPUT
        diff --git a/valid_file.rb b/valid_file.rb
        diff --git a/invalid_file.rb b/invalid_file.rb
      OUTPUT

      # Mock relative_to_root to filter out invalid_file.rb
      allow(Datadog::CI::Git::LocalRepository).to receive(:relative_to_root) do |path|
        (path == "valid_file.rb") ? "valid_file.rb" : ""
      end

      diff = described_class.parse_diff_output(git_output)
      expected_files = Set.new(["valid_file.rb"])
      expect(diff.to_set).to eq(expected_files)
    end

    it "ignores non-diff lines in the output" do
      git_output = <<~OUTPUT
        Some random output
        diff --git a/file1.rb b/file1.rb
        --- a/file1.rb
        +++ b/file1.rb
        This is not a diff line
        diff --git a/file2.rb b/file2.rb
        Another random line
      OUTPUT

      allow(Datadog::CI::Git::LocalRepository).to receive(:relative_to_root) do |path|
        path
      end

      diff = described_class.parse_diff_output(git_output)
      expected_files = Set.new(["file1.rb", "file2.rb"])
      expect(diff.to_set).to eq(expected_files)
    end
  end
end
