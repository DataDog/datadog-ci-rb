# frozen_string_literal: true

require "datadog/ci/git/diff"

RSpec.describe Datadog::CI::Git::Diff do
  before do
    # Mock relative_to_root to return the file paths as-is unless specified otherwise
    allow(Datadog::CI::Git::LocalRepository).to receive(:relative_to_root) do |path|
      path
    end
  end

  describe ".parse_diff_output" do
    context "with empty or nil output" do
      it "returns empty diff for nil output" do
        diff = described_class.parse_diff_output(nil)
        expect(diff.empty?).to be true
        expect(diff.size).to eq(0)
      end

      it "returns empty diff for empty output" do
        diff = described_class.parse_diff_output("")
        expect(diff.empty?).to be true
        expect(diff.size).to eq(0)
      end
    end

    context "with simple file changes" do
      it "parses a single file change" do
        git_output = <<~OUTPUT
          diff --git a/app/models/user.rb b/app/models/user.rb
          index 1234567..abcdefg 100644
          --- a/app/models/user.rb
          +++ b/app/models/user.rb
          @@ -1,3 +2,1 @@
           class User
          +  attr_accessor :name
           end
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.size).to eq(1)
        expect(diff.lines_changed?("app/models/user.rb", start_line: 2, end_line: 2)).to be true
        expect(diff.lines_changed?("app/models/user.rb", start_line: 1, end_line: 1)).to be false
        expect(diff.lines_changed?("other_file.rb", start_line: 1, end_line: 10)).to be false
        # Test the new nil argument functionality
        expect(diff.lines_changed?("app/models/user.rb")).to be true
        expect(diff.lines_changed?("other_file.rb")).to be false
        expect(diff.empty?).to be false
      end

      it "parses multiple file changes" do
        git_output = <<~OUTPUT
          diff --git a/app/models/user.rb b/app/models/user.rb
          index 1234567..abcdefg 100644
          --- a/app/models/user.rb
          +++ b/app/models/user.rb
          @@ -1,3 +2,1 @@
           class User
          +  attr_accessor :name
           end
          diff --git a/spec/models/user_spec.rb b/spec/models/user_spec.rb
          index 7890123..xyz9876 100644
          --- a/spec/models/user_spec.rb
          +++ b/spec/models/user_spec.rb
          @@ -5,2 +2,3 @@
           RSpec.describe User do
          +  it "has a name" do
          +    expect(User.new.name).to be_nil
          +  end
           end
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.size).to eq(2)
        expect(diff.lines_changed?("app/models/user.rb", start_line: 1, end_line: 4)).to be true
        expect(diff.lines_changed?("spec/models/user_spec.rb", start_line: 2, end_line: 4)).to be true
        expect(diff.lines_changed?("spec/models/user_spec.rb", start_line: 5, end_line: 5)).to be false
        expect(diff.lines_changed?("other_file.rb", start_line: 1, end_line: 10)).to be false
        # Test the new nil argument functionality for multiple files
        expect(diff.lines_changed?("app/models/user.rb")).to be true
        expect(diff.lines_changed?("spec/models/user_spec.rb")).to be true
        expect(diff.lines_changed?("other_file.rb")).to be false
      end
    end

    context "with nil keyword arguments" do
      it "returns true for files in diff when start_line is nil" do
        git_output = <<~OUTPUT
          diff --git a/app/models/user.rb b/app/models/user.rb
          @@ -10,4 +10,7 @@
           def initialize
             @name = nil
          +  @email = nil
           end
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("app/models/user.rb", end_line: 15)).to be true
        expect(diff.lines_changed?("app/models/user.rb", start_line: nil, end_line: 15)).to be true
      end

      it "returns true for files in diff when end_line is nil" do
        git_output = <<~OUTPUT
          diff --git a/app/models/user.rb b/app/models/user.rb
          @@ -10,4 +10,7 @@
           def initialize
             @name = nil
          +  @email = nil
           end
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("app/models/user.rb", start_line: 5)).to be true
        expect(diff.lines_changed?("app/models/user.rb", start_line: 5, end_line: nil)).to be true
      end

      it "returns true for files in diff when both arguments are nil" do
        git_output = <<~OUTPUT
          diff --git a/app/models/user.rb b/app/models/user.rb
          @@ -10,4 +10,7 @@
           def initialize
             @name = nil
          +  @email = nil
           end
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("app/models/user.rb")).to be true
        expect(diff.lines_changed?("app/models/user.rb", start_line: nil, end_line: nil)).to be true
      end

      it "returns false for files not in diff when arguments are nil" do
        git_output = <<~OUTPUT
          diff --git a/app/models/user.rb b/app/models/user.rb
          @@ -10,4 +10,7 @@
           def initialize
             @name = nil
          +  @email = nil
           end
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("app/models/post.rb")).to be false
        expect(diff.lines_changed?("app/models/post.rb", start_line: nil)).to be false
        expect(diff.lines_changed?("app/models/post.rb", end_line: nil)).to be false
        expect(diff.lines_changed?("app/models/post.rb", start_line: nil, end_line: nil)).to be false
      end

      it "returns false for files not in diff even with binary files" do
        git_output = <<~OUTPUT
          diff --git a/image.png b/image.png
          index 1234567..abcdefg 100644
          Binary files a/image.png and b/image.png differ
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("image.png")).to be true
        expect(diff.lines_changed?("image.png", start_line: nil)).to be true
        expect(diff.lines_changed?("image.png", end_line: nil)).to be true
        expect(diff.lines_changed?("other_file.png")).to be false
      end
    end

    context "with line change tracking" do
      it "tracks changed lines for a single interval" do
        git_output = <<~OUTPUT
          diff --git a/app/models/user.rb b/app/models/user.rb
          index 1234567..abcdefg 100644
          --- a/app/models/user.rb
          +++ b/app/models/user.rb
          @@ -10,4 +10,7 @@
           def initialize
             @name = nil
          +  @email = nil
          +  @phone = nil
           end
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("app/models/user.rb", start_line: 10, end_line: 16)).to be true
        expect(diff.lines_changed?("app/models/user.rb", start_line: 12, end_line: 14)).to be true
        expect(diff.lines_changed?("app/models/user.rb", start_line: 8, end_line: 9)).to be false
        expect(diff.lines_changed?("app/models/user.rb", start_line: 17, end_line: 20)).to be false
      end

      it "tracks changed lines for multiple intervals" do
        git_output = <<~OUTPUT
          diff --git a/app/models/user.rb b/app/models/user.rb
          index 1234567..abcdefg 100644
          --- a/app/models/user.rb
          +++ b/app/models/user.rb
          @@ -5,2 +5,3 @@
           class User
          +  include ActiveModel::Model
          @@ -15,3 +16,5 @@
           def save
             # validation logic
          +  validate_email
          +  validate_phone
           end
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        # First interval: lines 5-7 (start=5, count=3, end=5+3-1=7)
        expect(diff.lines_changed?("app/models/user.rb", start_line: 5, end_line: 7)).to be true
        expect(diff.lines_changed?("app/models/user.rb", start_line: 6, end_line: 6)).to be true

        # Second interval: lines 16-20 (start=16, count=5, end=16+5-1=20)
        expect(diff.lines_changed?("app/models/user.rb", start_line: 16, end_line: 20)).to be true
        expect(diff.lines_changed?("app/models/user.rb", start_line: 18, end_line: 20)).to be true

        # Between intervals: should be false
        expect(diff.lines_changed?("app/models/user.rb", start_line: 8, end_line: 15)).to be false
        expect(diff.lines_changed?("app/models/user.rb", start_line: 10, end_line: 15)).to be false

        # Outside intervals: should be false
        expect(diff.lines_changed?("app/models/user.rb", start_line: 1, end_line: 4)).to be false
        expect(diff.lines_changed?("app/models/user.rb", start_line: 21, end_line: 25)).to be false
      end

      it "returns false for lines_changed? when file is not in diff" do
        git_output = <<~OUTPUT
          diff --git a/app/models/user.rb b/app/models/user.rb
          @@ -5,2 +5,3 @@
           class User
          +  include ActiveModel::Model
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("app/models/post.rb", start_line: 1, end_line: 10)).to be false
        expect(diff.lines_changed?("non_existent.rb", start_line: 5, end_line: 15)).to be false
      end
    end

    context "with edge cases in git diff format" do
      it "handles single line additions (@@ -1 +1,2 @@)" do
        git_output = <<~OUTPUT
          diff --git a/config.rb b/config.rb
          @@ -1 +1,2 @@
           # Configuration
          +DEBUG = true
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("config.rb", start_line: 1, end_line: 2)).to be true
      end

      it "handles single line changes (@@ -5 +5 @@)" do
        git_output = <<~OUTPUT
          diff --git a/config.rb b/config.rb
          @@ -5 +5 @@
          -OLD_VALUE = 1
          +NEW_VALUE = 2
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("config.rb", start_line: 5, end_line: 5)).to be true
        expect(diff.lines_changed?("config.rb", start_line: 4, end_line: 4)).to be false
        expect(diff.lines_changed?("config.rb", start_line: 6, end_line: 6)).to be false
      end

      it "handles large line count changes" do
        git_output = <<~OUTPUT
          diff --git a/large_file.rb b/large_file.rb
          @@ -100,50 +100,75 @@
           # This is a large change
          +# Many new lines added
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("large_file.rb", start_line: 100, end_line: 174)).to be true
        expect(diff.lines_changed?("large_file.rb", start_line: 120, end_line: 150)).to be true
        expect(diff.lines_changed?("large_file.rb", start_line: 90, end_line: 99)).to be false
        expect(diff.lines_changed?("large_file.rb", start_line: 175, end_line: 200)).to be false
      end

      it "handles binary files" do
        git_output = <<~OUTPUT
          diff --git a/image.png b/image.png
          index 1234567..abcdefg 100644
          Binary files a/image.png and b/image.png differ
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("image.png", start_line: 1, end_line: 10)).to be false
      end

      it "handles new file creation" do
        git_output = <<~OUTPUT
          diff --git a/new_file.rb b/new_file.rb
          new file mode 100644
          index 0000000..1234567
          --- /dev/null
          +++ b/new_file.rb
          @@ -0,0 +1,5 @@
          +class NewFile
          +  def initialize
          +    @created = true
          +  end
          +end
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.lines_changed?("new_file.rb", start_line: 1, end_line: 5)).to be true
      end

      it "handles file deletion" do
        git_output = <<~OUTPUT
          diff --git a/deleted_file.rb b/deleted_file.rb
          deleted file mode 100644
          index 1234567..0000000
          --- a/deleted_file.rb
          +++ /dev/null
          @@ -1,5 +0,0 @@
          -class DeletedFile
          -  def initialize
          -    @deleted = true
          -  end
          -end
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        # Note: For deleted files, we still track them but there are no "new" lines
        expect(diff.lines_changed?("deleted_file.rb", start_line: 1, end_line: 5)).to be false
      end
    end

    context "with malformed or irregular git output" do
      it "ignores non-diff lines in the output" do
        git_output = <<~OUTPUT
          Some random output
          warning: LF will be replaced by CRLF
          diff --git a/file1.rb b/file1.rb
          @@ -1,2 +1,3 @@
           class File1
          +  # comment
           end
          This is not a diff line
          diff --git a/file2.rb b/file2.rb
          @@ -5,1 +5,2 @@
           def method
          +  # new line
          Another random line
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.size).to eq(2)
        expect(diff.lines_changed?("file1.rb", start_line: 1, end_line: 3)).to be true
        expect(diff.lines_changed?("file2.rb", start_line: 5, end_line: 6)).to be true
      end

      it "handles diff output without @@ lines" do
        git_output = <<~OUTPUT
          diff --git a/file1.rb b/file1.rb
          index 1234567..abcdefg 100644
          --- a/file1.rb
          +++ b/file1.rb
          diff --git a/file2.rb b/file2.rb
          index 7890123..xyz9876 100644
        OUTPUT

        diff = described_class.parse_diff_output(git_output)

        expect(diff.size).to eq(2)
        # No line changes recorded since there were no @@ lines
        expect(diff.lines_changed?("file1.rb", start_line: 1, end_line: 100)).to be false
        expect(diff.lines_changed?("file2.rb", start_line: 1, end_line: 100)).to be false
      end
    end
  end

  describe "#changed_line_intervals" do
    it "returns changed line intervals for a file" do
      git_output = <<~OUTPUT
        diff --git a/app/models/user.rb b/app/models/user.rb
        @@ -5,2 +5,3 @@
         class User
        +  include ActiveModel::Model
        @@ -15,3 +16,5 @@
         def save
        +  validate_email
        +  validate_phone
         end
      OUTPUT

      diff = described_class.parse_diff_output(git_output)
      intervals = diff.changed_line_intervals("app/models/user.rb")

      expect(intervals).to contain_exactly([5, 7], [16, 20])
    end

    it "returns empty array for file not in diff" do
      git_output = <<~OUTPUT
        diff --git a/app/models/user.rb b/app/models/user.rb
        @@ -5,2 +5,3 @@
         class User
        +  include ActiveModel::Model
      OUTPUT

      diff = described_class.parse_diff_output(git_output)
      intervals = diff.changed_line_intervals("non_existent.rb")

      expect(intervals).to eq([])
    end
  end

  describe "#inspect" do
    it "returns meaningful representation of the diff" do
      git_output = <<~OUTPUT
        diff --git a/file1.rb b/file1.rb
        @@ -1,2 +1,3 @@
         class File1
        +  # comment
         end
      OUTPUT

      diff = described_class.parse_diff_output(git_output)
      inspect_output = diff.inspect

      expect(inspect_output).to be_a(String)
      expect(inspect_output).to include("file1.rb")
    end
  end
end
