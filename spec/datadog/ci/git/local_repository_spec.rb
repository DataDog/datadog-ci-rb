require_relative "../../../../lib/datadog/ci/git/local_repository"

RSpec.describe ::Datadog::CI::Git::LocalRepository do
  include_context "Telemetry spy"

  before do
    # to make tests faster we lower the default timeout for all external calls
    stub_const("Datadog::CI::Utils::Command::DEFAULT_TIMEOUT", 0.5)
  end

  let(:environment_variables) { {} }

  def with_custom_git_environment
    ClimateControl.modify(environment_variables) do
      yield
    end
  end

  describe ".root" do
    subject { described_class.root }

    it { is_expected.to eq(Dir.pwd) }

    context "caches the result" do
      before do
        expect(Datadog::CI::Utils::Command).to receive(:exec_command).never
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

    # Clear the @prefix_to_root cache before each test to ensure isolation
    before do
      described_class.remove_instance_variable(:@prefix_to_root) if described_class.instance_variable_defined?(:@prefix_to_root)
    end

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

        context "when path is longer than root" do
          let(:path) { "/foo/bar/baz" }

          it { is_expected.to eq("baz") }
        end

        context "when path ends with separator" do
          let(:path) { "/foo/bar/baz/" }

          it { is_expected.to eq("baz/") }
        end

        context "when path is exactly the root" do
          let(:path) { "/foo/bar" }

          it { is_expected.to eq("") }
        end

        context "when path is equal to the root with a trailing slash" do
          let(:path) { "/foo/bar/" }

          it { is_expected.to eq("") }
        end

        context "when path is shorter than root" do
          let(:path) { "/foo" }

          it { is_expected.to eq("") }
        end

        context "when path looks kind of like a relative path from root but not really" do
          let(:path) { "/foo/barbaz" }

          it { is_expected.to eq("") }
        end

        context "when path has nested directories" do
          let(:path) { "/foo/bar/baz/qux/file.txt" }

          it { is_expected.to eq("baz/qux/file.txt") }
        end
      end

      context "when path is relative and the root is a parent directory" do
        before do
          allow(described_class).to receive(:root).and_return("#{Dir.pwd}/..")
        end

        context "when path starts with ./" do
          let(:path) { "./baz" }

          it "calculates correct relative path" do
            expect(subject).to eq("datadog-ci-rb/baz")
          end
        end

        context "when path starts with ./ and has nested directories" do
          let(:path) { "./baz/qux/file.txt" }

          it "calculates correct relative path with nested directories" do
            expect(subject).to eq("datadog-ci-rb/baz/qux/file.txt")
          end
        end

        context "when path doesn't start with ./" do
          let(:path) { "baz" }

          it { is_expected.to eq("datadog-ci-rb/baz") }
        end

        context "when @prefix_to_root is cached as empty string" do
          before do
            described_class.instance_variable_set(:@prefix_to_root, "")
          end

          let(:path) { "baz" }

          it { is_expected.to eq("baz") }
        end

        context "when @prefix_to_root is cached with a value" do
          before do
            described_class.instance_variable_set(:@prefix_to_root, "/foo/bar")
          end

          let(:path) { "baz" }

          it { is_expected.to eq("/foo/bar/baz") }
        end

        context "when path starts with ./ and @prefix_to_root is cached as empty" do
          before do
            described_class.instance_variable_set(:@prefix_to_root, "")
          end

          let(:path) { "./baz" }

          it "strips the ./ and returns the path" do
            # When @prefix_to_root is empty, it strips ./ (removes first character) and returns the path
            expect(subject).to eq("/baz")
          end
        end

        context "when path starts with ./ and @prefix_to_root is cached with value" do
          before do
            described_class.instance_variable_set(:@prefix_to_root, "/foo/bar")
          end

          let(:path) { "./baz" }

          it "strips the ./ and joins with prefix" do
            expect(subject).to eq("/foo/bar/baz")
          end
        end

        context "when multiple calls cache @prefix_to_root correctly" do
          before do
            allow(described_class).to receive(:root).and_return("#{Dir.pwd}/foo")
          end

          it "caches @prefix_to_root after first call" do
            # First call should calculate and cache @prefix_to_root
            first_result = described_class.relative_to_root("bar")
            expect(first_result).to eq("../bar")

            # Verify @prefix_to_root was cached
            expect(described_class.instance_variable_get(:@prefix_to_root)).to eq("../")

            # Second call should use cached value
            second_result = described_class.relative_to_root("baz")
            expect(second_result).to eq("../baz")
          end
        end

        context "when relative path calculation might return nil" do
          before do
            allow(described_class).to receive(:root).and_return("/tmp")
            # Mock Pathname to return nil from relative_path_from
            pathname_mock = double("pathname")
            allow(Pathname).to receive(:new).and_return(pathname_mock)
            allow(pathname_mock).to receive(:relative_path_from).and_return(nil)
          end

          let(:path) { "test" }

          it "returns empty string when result is nil" do
            expect(subject).to eq("")
          end
        end
      end

      context "edge cases" do
        before do
          allow(described_class).to receive(:root).and_return("/root")
        end

        context "when path contains special characters" do
          let(:path) { "/root/file with spaces.txt" }

          it { is_expected.to eq("file with spaces.txt") }
        end

        context "when path contains unicode characters" do
          let(:path) { "/root/файл.txt" }

          it { is_expected.to eq("файл.txt") }
        end

        context "when path has multiple separators" do
          let(:path) { "/root//double//separators" }

          it { is_expected.to eq("/double//separators") }
        end
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
        expect(Datadog::CI::Utils::Command).to receive(:exec_command).never
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

    it { is_expected.to include("DataDog/datadog-ci-rb") }

    it_behaves_like "emits telemetry metric", :inc, "git.command", 1
    it_behaves_like "emits telemetry metric", :distribution, "git.command_ms"
  end

  context "with git folder" do
    include_context "with git fixture", "gitdir_with_commit"

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

      it_behaves_like "emits telemetry metric", :inc, "git.command", 1
      it_behaves_like "emits telemetry metric", :distribution, "git.command_ms"
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

      context "when commit sha is provided" do
        subject do
          with_custom_git_environment do
            described_class.git_commit_users("c7f893648f656339f62fb7b4d8a6ecdf7d063835")
          end
        end

        it "parses author and commiter from the provided commit" do
          author, committer = subject

          expect(author.name).to eq("Friendly bot")
          expect(author.email).to eq("bot@friendly.test")
          expect(author.date).to eq("2011-02-16T13:00:00+00:00")
          expect(committer.name).to eq("Andrey Marchenko")
          expect(committer.email).to eq("andrey.marchenko@datadoghq.com")
          expect(committer.date).to eq("2023-10-02T13:52:56+00:00")
        end
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

      it_behaves_like "emits telemetry metric", :inc, "git.command", 1
      it_behaves_like "emits telemetry metric", :distribution, "git.command_ms"
    end

    describe ".git_commits_rev_list" do
      let(:included_commits) { [] }
      let(:excluded_commits) { [] }

      subject do
        with_custom_git_environment do
          described_class.git_commits_rev_list(included_commits: included_commits, excluded_commits: excluded_commits)
        end
      end

      it { is_expected.to be_nil }

      it_behaves_like "emits telemetry metric", :inc, "git.command", 1
      it_behaves_like "emits telemetry metric", :distribution, "git.command_ms"
    end
  end

  context "with git folder tagged" do
    include_context "with git fixture", "gitdir_with_tag"

    describe ".git_tag" do
      subject do
        with_custom_git_environment do
          described_class.git_tag
        end
      end

      it { is_expected.to eq("first-tag") }
    end
  end

  context "with failing command" do
    describe ".git_commits" do
      subject { described_class.git_commits }

      context "returns exit code 1" do
        before do
          expect(Datadog::CI::Utils::Command).to receive(:exec_command).and_return(["error", double(success?: false, to_i: 1)])
        end

        it { is_expected.to eq([]) }

        it_behaves_like "emits telemetry metric", :inc, "git.command_errors", 1

        it "tags error metric with command" do
          subject

          metric = telemetry_metric(:inc, "git.command_errors")
          expect(metric.tags).to eq({"command" => "get_local_commits", "exit_code" => "1"})
        end
      end

      context "git executable is missing" do
        before do
          expect(Datadog::CI::Utils::Command).to receive(:exec_command).and_raise(Errno::ENOENT.new("no file or directoru"))
        end

        it { is_expected.to eq([]) }

        it_behaves_like "emits telemetry metric", :inc, "git.command_errors", 1

        it "tags error metric with command" do
          subject

          metric = telemetry_metric(:inc, "git.command_errors")
          expect(metric.tags).to eq({"command" => "get_local_commits", "exit_code" => "missing"})
        end
      end
    end
  end
end
