# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/git/local_repository"

RSpec.describe ::Datadog::CI::Git::LocalRepository do
  include_context "Telemetry spy"

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

  context "with cloned repository" do
    let(:commits_count) { 2 }

    let(:tmpdir) { Dir.mktmpdir }

    let(:origin_path) { File.join(tmpdir, "repo_origin") }
    let(:source_path) { File.join(tmpdir, "source_repo") }

    let(:clone_folder_name) { "repo_clone" }
    let(:clone_path) { File.join(tmpdir, clone_folder_name) }

    def with_clone_git_dir
      ClimateControl.modify("GIT_DIR" => File.join(clone_path, ".git")) do
        yield
      end
    end

    before do
      `mkdir -p #{origin_path}`
      # create origin
      `cd #{origin_path} && git init --bare`

      # create a new git repository
      `mkdir -p #{source_path}`
      `cd #{source_path} && git init && git remote add origin #{origin_path}`
      if ENV["CI"] == "true"
        `cd #{source_path} && git config user.email "dev@datadoghq.com"`
        `cd #{source_path} && git config user.name "Bits"`
      end
      `cd #{source_path} && echo "Hello, world!" >> README.md && git add README.md && git commit -m "Initial commit"`

      commits_count.times do
        `cd #{source_path} && echo "Hello, world!" >> README.md && git add README.md && git commit -m "Update README"`
      end
      `cd #{source_path} && git push origin master`
    end

    after { FileUtils.remove_entry(tmpdir) }

    context "with shallow clone" do
      before do
        # create a shallow clone
        `cd #{tmpdir} && git clone --depth=1 file://#{origin_path} #{clone_folder_name}`
      end

      describe ".git_shallow_clone?" do
        subject do
          with_clone_git_dir { described_class.git_shallow_clone? }
        end

        it { is_expected.to be_truthy }
      end

      describe ".git_commits" do
        subject do
          with_clone_git_dir { described_class.git_commits }
        end

        it "returns a list of single git commit sha" do
          expect(subject).to be_kind_of(Array)
          expect(subject).not_to be_empty
          expect(subject).to have(1).item
          expect(subject.first).to match(/^\h{40}$/)
        end
      end

      describe ".git_unshallow" do
        subject do
          with_clone_git_dir { described_class.git_unshallow }
        end
        let(:commits) do
          with_clone_git_dir { described_class.git_commits }
        end

        context "successful from the first try" do
          before do
            expect(Open3).to receive(:capture2e).and_call_original.at_most(2).times
          end

          it "unshallows the repository" do
            expect(subject).to be_truthy
            # additional commits plus the initial commit
            expect(commits.size).to eq(commits_count + 1)
          end
        end

        context "when unshallow command fails" do
          before do
            allow(Open3).to receive(:capture2e).and_call_original
            allow(Open3).to receive(:capture2e)
              .with("git fetch --shallow-since=\"1 month ago\" --update-shallow --filter=\"blob:none\" --recurse-submodules=no $(git config --default origin --get clone.defaultRemoteName) $(git rev-parse HEAD)", stdin_data: nil)
              .and_return(["error", double(success?: false, to_i: 1)])
          end

          it "still unshallows the repository using the fallback command" do
            expect(subject).to be_truthy
            # additional commits plus the initial commit
            expect(commits.size).to eq(commits_count + 1)
          end

          # it signals error to the telemetry
          it_behaves_like "emits telemetry metric", :inc, "git.command_errors", 1
        end
      end
    end

    context "with full clone" do
      before do
        # create a full clone
        `cd #{tmpdir} && git clone file://#{origin_path} #{clone_folder_name}`
      end

      describe ".git_commits" do
        subject { with_clone_git_dir { described_class.git_commits } }

        it "returns a list of git commit sha" do
          expect(subject).to be_kind_of(Array)
          expect(subject).not_to be_empty
          expect(subject.first).to eq(
            with_clone_git_dir do
              described_class.git_commit_sha
            end
          )
        end
      end

      describe ".git_commits_rev_list" do
        let(:commits) { with_clone_git_dir { described_class.git_commits } }
        let(:included_commits) { commits[0..1] }
        let(:excluded_commits) { commits[2..] }

        subject do
          with_clone_git_dir do
            described_class.git_commits_rev_list(included_commits: included_commits, excluded_commits: excluded_commits)
          end
        end

        it "returns a list of commits that are reachable from included list but not reachable from excluded list" do
          expect(subject).to include(included_commits.join("\n"))
          expect(subject).not_to include(excluded_commits.first)
        end

        context "invalid commits" do
          let(:included_commits) { [" | echo \"boo\" "] }
          let(:excluded_commits) { [" | echo \"boo\" "] }

          it "returns nil" do
            expect(subject).to be_nil
          end
        end
      end

      describe ".git_generate_packfiles" do
        let(:commits) { with_clone_git_dir { described_class.git_commits } }
        let(:included_commits) { commits[0..1] }
        let(:excluded_commits) { commits[2..] }

        subject do
          with_clone_git_dir do
            described_class.git_generate_packfiles(
              included_commits: included_commits,
              excluded_commits: excluded_commits,
              path: packfiles_dir
            )
          end
        end

        context "temporary directory" do
          let(:packfiles_dir) { File.join(tmpdir, "packfiles") }
          before do
            `mkdir -p #{packfiles_dir}`
          end

          it "generates packfiles in temp directory" do
            expect(subject).to match(/^\h{8}$/)
            packfiles = Dir.entries(packfiles_dir) - %w[. ..]
            expect(packfiles).not_to be_empty
            expect(packfiles).to all(match(/^\h{8}-\h{40}\.(pack|idx|rev)$/))
          end
        end

        context "no such directory" do
          let(:packfiles_dir) { " | echo \"boo\"" }

          it "returns nil" do
            expect(subject).to be_nil
            expect(File.exist?(packfiles_dir)).to be_falsey
          end
        end
      end

      describe ".git_shallow_clone?" do
        subject do
          with_clone_git_dir { described_class.git_shallow_clone? }
        end

        it { is_expected.to be_falsey }
      end
    end
  end

  context "with failing command" do
    describe ".git_commits" do
      subject { described_class.git_commits }

      context "succeeds on retries" do
        before do
          expect(Open3).to receive(:capture2e).and_return([nil, nil], [+"sha1\nsha2", double(success?: true)])
        end

        it { is_expected.to eq(%w[sha1 sha2]) }
      end

      context "fails on retries" do
        before do
          expect(Open3).to(
            receive(:capture2e)
              .and_return([nil, nil])
              .at_most(described_class::COMMAND_RETRY_COUNT + 1)
              .times
          )
        end

        it { is_expected.to eq([]) }

        it_behaves_like "emits telemetry metric", :inc, "git.command_errors", 1

        it "tags error metric with command" do
          subject

          metric = telemetry_metric(:inc, "git.command_errors")
          expect(metric.tags).to eq({"command" => "get_local_commits"})
        end
      end

      context "returns exit code 1" do
        before do
          expect(Open3).to receive(:capture2e).and_return(["error", double(success?: false, to_i: 1)])
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
          expect(Open3).to receive(:capture2e).and_raise(Errno::ENOENT.new("no file or directoru"))
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
