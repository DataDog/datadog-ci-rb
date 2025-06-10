require_relative "../../../../lib/datadog/ci/git/local_repository"

RSpec.describe ::Datadog::CI::Git::LocalRepository do
  include_context "Telemetry spy"

  let(:commits_count) { 2 }

  let(:tmpdir) { Dir.mktmpdir }

  # repositories:
  # - source is where we create the repo and add some commits
  # - origin is the remote repository that we push to
  # - clone is the local repository that we clone from origin
  let(:origin_path) { File.join(tmpdir, "repo_origin") }
  let(:source_path) { File.join(tmpdir, "source_repo") }

  let(:clone_folder_name) { "repo_clone" }
  let(:clone_path) { File.join(tmpdir, clone_folder_name) }

  # branches:
  # - base_branch is the default branch (let's imagine we have a PR targeting this branch)
  # - feature_branch is the branch with new changes that we want to merge into base
  let(:base_branch) { "master" }
  let(:feature_branch) { "feature" }

  let(:base_file) { "base.txt" }
  let(:not_changed_file) { "not_changed.txt" }
  let(:feature_file) { "feature.txt" }

  let(:file_to_rename) { "file_to_rename.txt" }
  let(:renamed_file) { "renamed_file.txt" }

  def create_source_repo_and_push_to_origin
    system("mkdir -p #{origin_path}")

    Dir.chdir(origin_path) do
      system("git init --bare")
    end

    # create a new git repository
    system("mkdir -p #{source_path}")

    Dir.chdir(source_path) do
      system("git init")
      system("git remote add origin #{origin_path}")
      if ENV["CI"] == "true"
        system("git config user.email 'dev@datadoghq.com'")
        system("git config user.name 'Bits'")
      end

      system("echo 'Hello, world!' >> README.md")
      system("git add README.md")
      system("git commit -m 'Initial commit'")

      commits_count.times do
        system("echo 'Hello, world!' >> README.md")
        system("git add README.md")
        system("git commit -m 'Update README'")
      end

      system("git push origin master")
    end
  end

  def with_source_git_dir
    ClimateControl.modify("GIT_DIR" => File.join(source_path, ".git")) do
      yield
    end
  end

  def with_clone_git_dir
    ClimateControl.modify("GIT_DIR" => File.join(clone_path, ".git")) do
      yield
    end
  end

  before do
    create_source_repo_and_push_to_origin
  end

  after { FileUtils.remove_entry(tmpdir) }

  context "with multiline commit message" do
    before do
      Dir.chdir(source_path) do
        system("echo 'Hello, world!' >> README.md")
        system("git add README.md")
        system("git commit -m 'Initial commit\n\nThis is a multiline commit message'")
      end
    end

    describe ".git_commit_message" do
      subject do
        with_source_git_dir do
          described_class.git_commit_message
        end
      end

      it "returns the multiline commit message" do
        expect(subject).to eq("Initial commit\n\nThis is a multiline commit message")
      end
    end
  end

  context "with multiple git messages" do
    before do
      Dir.chdir(source_path) do
        system("echo 'Hello, world!' >> README.md")
        system("git add README.md")
        system("git commit -m 'Initial commit' -m 'More details'")
      end
    end

    describe ".git_commit_message" do
      subject do
        with_source_git_dir { described_class.git_commit_message }
      end

      it "returns the commit message" do
        expect(subject).to eq("Initial commit\n\nMore details")
      end
    end
  end

  context "with feature branch" do
    # add additional commits to the base branch and push it to origin
    # returns the SHA of the last commit
    def build_base_branch
      Dir.chdir(source_path) do
        system("git checkout #{base_branch}")
        system("echo 'base branch file' >> #{base_file}")
        system("echo 'not changed file' >> #{not_changed_file}")
        system("echo 'file to rename' >> #{file_to_rename}")
        system("git add #{base_file} #{not_changed_file} #{file_to_rename}")
        system("git commit -m 'Add base file'")
        system("git push origin #{base_branch}")
        `git rev-parse HEAD`.strip
      end
    end

    # create a new branch "feature" and adds more commits there: a new file, a modified file, a renamed file
    # commits and pushes to origin
    # returns the SHA of the last commit
    def build_feature_branch
      Dir.chdir(source_path) do
        system("git checkout -b #{feature_branch}")
        system("echo 'feature branch file' >> #{feature_file}")
        system("echo 'modified in feature branch' >> #{base_file}")
        system("mv #{file_to_rename} #{renamed_file}")
        system("git add -A")
        system("git commit -m 'Add feature file and modify base file'")
        system("git push origin #{feature_branch}")
        `git rev-parse HEAD`.strip
      end
    end

    describe ".get_changes_since" do
      it "detects changed files between feature and base branch" do
        # avoids cached git root from previous test cases
        allow(described_class).to receive(:root).and_return(nil)

        # Setup branches and commits
        base_sha = build_base_branch
        build_feature_branch

        # Now diff from feature branch to base branch
        changed_files = nil
        with_source_git_dir do
          changed_files = described_class.get_changes_since(base_sha)
        end

        expect(changed_files).to be_a(Set)
        # Should includes all modified and renamed files
        expect(changed_files).to eq(Set.new([base_file, feature_file, file_to_rename]))
      end

      context "with malicious input that could cause ReDoS" do
        it "handles pathological diff output without catastrophic backtracking" do
          # Create a malicious git diff output that would cause catastrophic backtracking
          # with the vulnerable regex /^diff --git a\/(?<file>.+) b\/(?<file2>.+)$/
          # The pattern "a b/a b/a b/..." repeated many times would cause exponential backtracking
          malicious_path = "a b/" * 50 + "file.txt"
          malicious_diff_output = "diff --git a/#{malicious_path} b/#{malicious_path}\n" \
                                 "--- a/#{malicious_path}\n" \
                                 "+++ b/#{malicious_path}\n" \
                                 "@@ -1 +1 @@\n" \
                                 "-old content\n" \
                                 "+new content\n"
          expected_path = "a"

          # Mock the git command to return our malicious output
          allow(Datadog::CI::Git::CLI).to receive(:exec_git_command)
            .with(anything, timeout: anything)
            .and_return(malicious_diff_output)

          # With the non-greedy regex, it will only capture "a" (up to the first " b/")
          # Mock relative_to_root to return a simple path
          allow(described_class).to receive(:relative_to_root)
            .with(expected_path)
            .and_return(expected_path)

          # This should complete quickly without timing out
          result = nil
          duration_ms = Datadog::Core::Utils::Time.measure(:float_millisecond) do
            result = described_class.get_changes_since("base_commit_sha")
          end

          # Should complete in under 1000 milliseconds (vulnerable regex would take much longer)
          expect(duration_ms).to be < 1000.0
          expect(result).to be_a(Set)
          # The non-greedy regex will extract "a" from the malicious path
          expect(result).to include(expected_path)
        end
      end
    end

    describe ".base_commit_sha" do
      it "returns the ref from the base branch" do
        expected_base_sha = build_base_branch
        build_feature_branch

        base_sha = nil
        with_source_git_dir do
          base_sha = described_class.base_commit_sha
        end

        expect(base_sha).to eq(expected_base_sha)
      end

      context "when repository is cloned from remote" do
        context "with fresh clone where remote branch is cloned into master branch of the local repository" do
          def clone_from_remote_into_local_master_branch
            `mkdir -p #{clone_path}`
            Dir.chdir(clone_path) do
              system("git init")
              system("git remote add origin file://#{origin_path}")
              system("git fetch origin #{feature_branch}")
              system("git reset --hard origin/#{feature_branch}")
            end
          end

          it "returns the ref from default branch" do
            expected_base_sha = build_base_branch
            build_feature_branch
            clone_from_remote_into_local_master_branch

            base_sha = nil
            with_clone_git_dir do
              base_sha = described_class.base_commit_sha
            end

            expect(base_sha).to eq(expected_base_sha)
          end

          context "when base branch is provided" do
            it "returns the ref from the base branch" do
              expected_base_sha = build_base_branch
              build_feature_branch
              clone_from_remote_into_local_master_branch

              base_sha = nil
              with_clone_git_dir do
                base_sha = described_class.base_commit_sha(base_branch: "master")
              end

              expect(base_sha).to eq(expected_base_sha)
            end

            it "returns the ref from the base branch when base branch has remote prefix" do
              expected_base_sha = build_base_branch
              build_feature_branch
              clone_from_remote_into_local_master_branch

              base_sha = nil
              with_clone_git_dir do
                base_sha = described_class.base_commit_sha(base_branch: "origin/master")
              end

              expect(base_sha).to eq(expected_base_sha)
            end
          end
        end

        context "when remote is pointing to non existing repository" do
          def create_new_repo_with_non_existing_remote
            `mkdir -p #{clone_path}`

            Dir.chdir(clone_path) do
              system("git init")
              system("echo 'base branch file' >> #{base_file}")
              system("git add -A")
              system("git commit -m 'first commit'")
              system("git remote add origin git@git.com:datadog/non_existing_repo.git")
            end
          end

          it "returns nil" do
            build_base_branch
            build_feature_branch
            create_new_repo_with_non_existing_remote

            base_sha = nil
            with_clone_git_dir do
              base_sha = described_class.base_commit_sha
            end

            expect(base_sha).to be_nil
          end
        end

        context "with fresh clone where only the feature branch exists (repo cloned in GitHub Actions style)" do
          def clone_only_feature_branch
            `mkdir -p #{clone_path}`
            Dir.chdir(clone_path) do
              system("git init")
              system("git remote add origin file://#{origin_path}")
              system("git fetch --no-tags --prune --no-recurse-submodules origin #{feature_branch}")
              system("git checkout --progress --force -B #{feature_branch} refs/remotes/origin/#{feature_branch}")
            end
          end

          it "returns the ref from default branch" do
            expected_base_sha = build_base_branch
            build_feature_branch
            clone_only_feature_branch

            base_sha = nil
            with_clone_git_dir do
              base_sha = described_class.base_commit_sha
            end

            expect(base_sha).to eq(expected_base_sha)
          end

          context "when base branch is provided" do
            it "returns the ref from the base branch" do
              expected_base_sha = build_base_branch
              build_feature_branch
              clone_only_feature_branch

              base_sha = nil
              with_clone_git_dir do
                base_sha = described_class.base_commit_sha(base_branch: "master")
              end

              expect(base_sha).to eq(expected_base_sha)
            end
          end
        end
      end

      context "with preprod branch" do
        let(:preprod_branch) { "preprod" }
        let(:new_feature_branch) { "new-feature" }

        # we use preprod branch to test a case where there are several base branch candidates
        # from the current branch create a new branch "preprod" and adds more commits there
        # returns the SHA of the latest commit
        def build_preprod_branch
          Dir.chdir(source_path) do
            system("git checkout -b #{preprod_branch}")
            system("echo 'preprod changes' >> #{feature_file}")
            system("git add #{feature_file}")
            system("git commit -m 'Add preprod changes'")
            system("git push origin #{preprod_branch}")
            `git rev-parse HEAD`.strip
          end
        end

        # new-feature branch is forked from preprod branch
        # from the current branch create a new branch "new-feature" and adds more commits there
        # returns the SHA of the latest commit
        def build_new_feature_branch
          Dir.chdir(source_path) do
            system("git checkout -b #{new_feature_branch}")
            system("echo 'new feature changes' >> #{feature_file}")
            system("git add #{feature_file}")
            system("git commit -m 'Add new feature changes'")
            system("git push origin #{new_feature_branch}")
            `git rev-parse HEAD`.strip
          end
        end

        it "returns the ref from preprod branch" do
          build_base_branch
          expected_base_sha = build_preprod_branch
          build_new_feature_branch

          base_sha = nil
          with_source_git_dir do
            base_sha = described_class.base_commit_sha
          end

          expect(base_sha).to eq(expected_base_sha)
        end

        context "when base branch is provided" do
          it "returns the ref from the base branch" do
            expected_base_sha = build_base_branch
            build_preprod_branch
            build_new_feature_branch

            base_sha = nil
            with_source_git_dir do
              base_sha = described_class.base_commit_sha(base_branch: "master")
            end

            expect(base_sha).to eq(expected_base_sha)
          end
        end
      end
    end
  end

  context "with shallow clone" do
    before do
      # create a shallow clone
      Dir.chdir(tmpdir) do
        system("git clone --depth=1 file://#{origin_path} #{clone_folder_name}")
      end
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
          # We now make more calls: config, rev-parse HEAD, rev-parse upstream, and fetch
          expect(Datadog::CI::Utils::Command).to receive(:exec_command).and_call_original.at_most(5).times
        end

        it "unshallows the repository" do
          expect(subject).to be_truthy
          # additional commits plus the initial commit
          expect(commits.size).to eq(commits_count + 1)
        end
      end

      context "when unshallow command fails" do
        before do
          head_commit = "sha"
          allow(Datadog::CI::Utils::Command).to receive(:exec_command).and_call_original
          allow(Datadog::CI::Utils::Command).to receive(:exec_command)
            .with(["git", "rev-parse", "HEAD"], stdin_data: nil, timeout: Datadog::CI::Git::CLI::SHORT_TIMEOUT)
            .and_return([head_commit, double(success?: true)])

          # Mock the fetch command with the head commit to fail
          allow(Datadog::CI::Utils::Command).to receive(:exec_command)
            .with(
              ["git", "fetch", "--shallow-since=\"1 month ago\"", "--update-shallow", "--filter=blob:none", "--recurse-submodules=no", "origin", head_commit],
              stdin_data: nil, timeout: Datadog::CI::Git::CLI::UNSHALLOW_TIMEOUT
            )
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
      Dir.chdir(tmpdir) do
        system("git clone file://#{origin_path} #{clone_folder_name}")
      end
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
