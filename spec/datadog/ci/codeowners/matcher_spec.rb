require "datadog/ci/codeowners/matcher"

RSpec.describe Datadog::CI::Codeowners::Matcher do
  # most of the examples here are from the following sources:
  # https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
  # https://docs.gitlab.com/ee/user/project/codeowners/reference.html
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
        expect(matcher.list_owners("file.rb")).to be_nil
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
        expect(matcher.list_owners("/path/to/another_file.rb")).to be_nil
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

          [section2][2]
          /path/to/file.rb @owner1
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("/path/to/file.rb")).to eq(["@owner1"])
        expect(matcher.list_owners("/path/to/another_file.rb")).to eq(["@owner2"])
      end
    end

    context "with global pattern" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          * @owner1
          /path/to/file.rb @owner2
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("/path/to/file.rb")).to eq(["@owner2"])
        expect(matcher.list_owners("/path/to/another_file.rb")).to eq(["@owner1"])
      end
    end

    context "with file extension patterns" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          *.js @jsowner
          *.go @Datadog/goowner
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("/path/to/file.js")).to eq(["@jsowner"])
        expect(matcher.list_owners("main.go")).to eq(["@Datadog/goowner"])
      end
    end

    context "when matching directory and all subdirectories" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          * @owner

          # In this example, @buildlogsowner owns any files in the build/logs
          # directory at the root of the repository and any of its
          # subdirectories.
          /build/logs/ @buildlogsowner
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("/build/logs/logs.txt")).to eq(["@buildlogsowner"])
        expect(matcher.list_owners("build/logs/2022/logs.txt")).to eq(["@buildlogsowner"])
        expect(matcher.list_owners("/build/logs/2022/12/logs.txt")).to eq(["@buildlogsowner"])
        expect(matcher.list_owners("build/logs/2022/12/logs.txt")).to eq(["@buildlogsowner"])

        expect(matcher.list_owners("/service/build/logs/logs.txt")).to eq(["@owner"])
        expect(matcher.list_owners("service/build/build.pkg")).to eq(["@owner"])
      end
    end

    context "when matching files in a directory but not in subdirectories" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          * @owner

          # The `docs/*` pattern will match files like
          # `docs/getting-started.md` but not further nested files like
          # `docs/build-app/troubleshooting.md`.
          docs/*  docs@example.com
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("docs/getting-started.md")).to eq(["docs@example.com"])
        expect(matcher.list_owners("docs/build-app/troubleshooting.md")).to eq(["@owner"])

        expect(matcher.list_owners("some/folder/docs/getting-started.md")).to eq(["docs@example.com"])
        expect(matcher.list_owners("some/folder/docs/build-app/troubleshooting.md")).to eq(["@owner"])

        expect(matcher.list_owners("/root/docs/getting-started.md")).to eq(["docs@example.com"])
        expect(matcher.list_owners("/root/folder/docs/build-app/troubleshooting.md")).to eq(["@owner"])
      end
    end

    context "when matching files in any subdirectory anywhere in the repository" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          * @owner

          # In this example, @octocat owns any file in an apps directory
          # anywhere in your repository.
          apps/ @octocat
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("/apps/file.txt")).to eq(["@octocat"])
        expect(matcher.list_owners("/some/folder/apps/file.txt")).to eq(["@octocat"])
        expect(matcher.list_owners("some/folder/apps/1/file.txt")).to eq(["@octocat"])
        expect(matcher.list_owners("some/folder/apps/1/2/file.txt")).to eq(["@octocat"])

        expect(matcher.list_owners("file.txt")).to eq(["@owner"])
        expect(matcher.list_owners("/file.txt")).to eq(["@owner"])
        expect(matcher.list_owners("some/folder/file.txt")).to eq(["@owner"])
      end
    end

    context "when pattern starts from **" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          * @owner

          # In this example, @octocat owns any file in a `/logs` directory such as
          # `/build/logs`, `/scripts/logs`, and `/deeply/nested/logs`. Any changes
          # in a `/logs` directory will require approval from @octocat.
          **/logs @octocat
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("/build/logs/logs.txt")).to eq(["@octocat"])
        expect(matcher.list_owners("/scripts/logs/logs.txt")).to eq(["@octocat"])
        expect(matcher.list_owners("/deeply/nested/logs/logs.txt")).to eq(["@octocat"])
        expect(matcher.list_owners("/logs/logs.txt")).to eq(["@octocat"])

        expect(matcher.list_owners("file.txt")).to eq(["@owner"])
        expect(matcher.list_owners("/file.txt")).to eq(["@owner"])
        expect(matcher.list_owners("some/folder/file.txt")).to eq(["@owner"])
      end
    end

    context "when matching anywhere in directory but not in specific subdirectory" do
      let(:codeowners_content) do
        <<-CODEOWNERS
          * @owner

          # In this example, @octocat owns any file in the `/apps`
          # directory in the root of your repository except for the `/apps/github`
          # subdirectory, as its owners are left empty.
          /apps/ @octocat
          /apps/github
        CODEOWNERS
      end

      it "returns the list of owners for the matching pattern" do
        expect(matcher.list_owners("/apps/logs.txt")).to eq(["@octocat"])
        expect(matcher.list_owners("/apps/1/logs.txt")).to eq(["@octocat"])
        expect(matcher.list_owners("/apps/deeply/nested/logs/logs.txt")).to eq(["@octocat"])

        expect(matcher.list_owners("apps/github")).to eq([])
        expect(matcher.list_owners("apps/github/codeowners")).to eq([])

        expect(matcher.list_owners("other/file.txt")).to eq(["@owner"])
      end
    end
  end
end
