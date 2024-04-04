# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/git/local_repository"

RSpec.describe ::Datadog::CI::Git::LocalRepository do
  let(:environment_variables) { {} }

  describe ".root" do
    subject { described_class.root }

    it { is_expected.to eq(Dir.pwd) }

    context "caches the result" do
      before do
        expect(Open3).to receive(:capture2e).never
      end

      it "returns the same result" do
        2.times do
          expect(described_class.root).to eq(Dir.pwd)
        end
      end
    end
  end

  describe ".relative_to_root" do
    subject { described_class.relative_to_root(path) }

    context "when path is nil" do
      let(:path) { nil }

      it { is_expected.to eq("") }
    end

    context "when git root is nil" do
      before do
        allow(described_class).to receive(:root).and_return(nil)
      end

      let(:path) { "foo/bar" }

      it { is_expected.to eq("foo/bar") }
    end

    context "when git root is not nil" do
      context "when path is absolute" do
        before do
          allow(described_class).to receive(:root).and_return("/foo/bar")
        end
        let(:path) { "/foo/bar/baz" }

        it { is_expected.to eq("baz") }
      end

      context "when path is relative" do
        before do
          allow(described_class).to receive(:root).and_return("#{Dir.pwd}/foo/bar")
        end

        let(:path) { "./baz" }

        it { is_expected.to eq("../../baz") }
      end
    end
  end

  describe ".current_folder_name" do
    subject { described_class.current_folder_name }
    let(:path) { "/foo/bar" }

    before do
      allow(described_class).to receive(:root).and_return(path)
    end

    it { is_expected.to eq("bar") }
  end

  describe ".repository_name" do
    subject { described_class.repository_name }

    it { is_expected.to eq("datadog-ci-rb") }

    context "caches the result" do
      before do
        expect(Open3).to receive(:capture2e).never
      end

      it "returns the same result" do
        2.times do
          expect(described_class.root).to eq(Dir.pwd)
        end
      end
    end
  end

  describe ".git_repository_url" do
    subject { described_class.git_repository_url }

    it { is_expected.to eq("git@github.com:DataDog/datadog-ci-rb.git") }
  end

  describe ".git_commits" do
    subject { described_class.git_commits }

    it "returns a list of git commit sha (this test will fail if there are no commits to this library in the past month)" do
      expect(subject).to be_kind_of(Array)
      expect(subject).not_to be_empty
      expect(subject.first).to eq(described_class.git_commit_sha)
    end
  end

  context "with git folder" do
    include_context "with git fixture", "gitdir_with_commit"

    def with_custom_git_environment
      ClimateControl.modify(environment_variables) do
        yield
      end
    end

    describe ".git_root" do
      subject do
        with_custom_git_environment do
          described_class.git_root
        end
      end

      it { is_expected.to eq(File.join(Dir.pwd, "spec/support/fixtures/git")) }
    end

    describe ".git_commit_sha" do
      subject do
        with_custom_git_environment do
          described_class.git_commit_sha
        end
      end

      it { is_expected.to eq("c7f893648f656339f62fb7b4d8a6ecdf7d063835") }
    end

    describe ".git_branch" do
      subject do
        with_custom_git_environment do
          described_class.git_branch
        end
      end

      it { is_expected.to eq("master") }
    end

    describe ".git_tag" do
      subject do
        with_custom_git_environment do
          described_class.git_tag
        end
      end

      it { is_expected.to be_nil }
    end

    describe ".git_commit_message" do
      subject do
        with_custom_git_environment do
          described_class.git_commit_message
        end
      end

      it { is_expected.to eq("First commit with ❤️") }
    end

    describe ".git_commit_users" do
      subject do
        with_custom_git_environment do
          described_class.git_commit_users
        end
      end

      it "parses author and commiter from the latest commit" do
        author, committer = subject

        expect(author.name).to eq("Friendly bot")
        expect(author.email).to eq("bot@friendly.test")
        expect(author.date).to eq("2011-02-16T13:00:00+00:00")
        expect(committer.name).to eq("Andrey Marchenko")
        expect(committer.email).to eq("andrey.marchenko@datadoghq.com")
        expect(committer.date).to eq("2023-10-02T13:52:56+00:00")
      end
    end

    describe ".git_commits" do
      subject do
        with_custom_git_environment do
          described_class.git_commits
        end
      end

      it "returns empty array as last commit was more than 1 month ago" do
        expect(subject).to eq([])
      end
    end
  end
end
