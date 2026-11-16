# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "Git checkout metadata" do
  def git(*args, directory: @workspace, input: "")
    output, status = Open3.capture2e("git", "-C", directory, *args, stdin_data: input)
    raise output unless status.success?

    output.strip
  end

  def clear_checkout_cache
    [
      [Datadog::CI::Git::CLI, %i[@safe_directory @working_directory]],
      [Datadog::CI::Git::LocalRepository, %i[@root @prefix_to_root @repository_name]]
    ].each do |owner, variables|
      variables.each { |name| owner.remove_instance_variable(name) if owner.instance_variable_defined?(name) }
    end
    Datadog::CI::Ext::Environment.reset!
  end

  around do |example|
    Dir.mktmpdir("checkout-context") do |directory|
      @workspace = File.join(directory, "workspace")
      @nested = File.join(@workspace, "tools")
      [@workspace, @nested].each do |checkout|
        FileUtils.mkdir_p(checkout)
        FileUtils.cp_r(File.join(FIXTURE_DIR, "git/gitdir_with_commit"), File.join(checkout, ".git"))
      end
      ClimateControl.modify("GIT_DIR" => nil, "GIT_WORK_TREE" => nil, "GIT_COMMON_DIR" => nil,
        "GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1") do
        clear_checkout_cache
        @head = git("rev-parse", "HEAD")
        @alias = File.join(directory, "workspace-alias")
        File.symlink(@workspace, @alias)
        Dir.chdir(@workspace) { example.run }
      ensure
        clear_checkout_cache
      end
    end
  end

  scenarios = [
    {name: "matching GitHub checkout"},
    {name: "matching GitLab mirror", gitlab: true},
    {name: "workspace symlink", symlink: true},
    {name: "different revision", mismatch: true},
    {name: "nested checkout with matching revision", nested: true},
    {name: "missing workspace", missing_workspace: true},
    {name: "missing provider revision", missing_sha: true},
    {name: "attached branch", attached: true},
    {name: "attached branch pointing at a release", attached: true, local_tag: true},
    {name: "explicit identity", overrides: true},
    {name: "release without local tags", release: true},
    {name: "release with ambiguous local tags", release: true, ambiguous: true},
    {name: "release at another revision", release: true, mismatch: true},
    {name: "nested release checkout", release: true, nested: true}
  ]
  scenarios.each do |scenario|
    it "selects identity for #{scenario[:name]}" do
      checkout = scenario[:nested] ? @nested : @workspace
      git("config", "remote.origin.url", "https://mirror.example.com/repository.git", directory: checkout)
      git("checkout", "--detach", "HEAD", directory: checkout) unless scenario[:attached]
      git("update-ref", "refs/tags/v1", @head, directory: checkout) if scenario[:local_tag]
      if scenario[:ambiguous]
        %w[v1 stable].each { |tag| git("update-ref", "refs/tags/#{tag}", @head, directory: checkout) }
      end
      provider_sha = if scenario[:missing_sha]
        nil
      else
        scenario[:mismatch] ? "a" * 40 : @head
      end
      workspace = if scenario[:missing_workspace]
        nil
      else
        scenario[:symlink] ? @alias : @workspace
      end
      env = if scenario[:gitlab]
        {"GITLAB_CI" => "true", "CI_COMMIT_SHA" => provider_sha, "CI_COMMIT_REF_NAME" => "ci-branch",
         "CI_PROJECT_DIR" => workspace, "CI_REPOSITORY_URL" => "https://example.com/project.git"}
      else
        {"GITHUB_SHA" => provider_sha, "GITHUB_REF" => scenario[:release] ? "refs/tags/v1" : "refs/heads/ci-branch",
         "GITHUB_WORKSPACE" => workspace, "GITHUB_SERVER_URL" => "https://example.com", "GITHUB_REPOSITORY" => "project/repository"}
      end
      canonical_url = scenario[:gitlab] ? "https://example.com/project.git" : "https://example.com/project/repository.git"
      if scenario[:overrides]
        env["DD_GIT_BRANCH"] = "user-branch"
        env["DD_GIT_REPOSITORY_URL"] = "https://example.com/user.git"
      end
      metadata = Dir.chdir(checkout) { Datadog::CI::Ext::Environment.tags(env) }
      matched = !scenario.values_at(:nested, :missing_workspace, :missing_sha, :mismatch, :attached).any?
      expect(metadata["git.commit.sha"]).to eq(@head)
      expect(metadata["git.checkout.root"]).to eq(File.realpath(checkout))
      expect(metadata["ci.workspace_path"]).to eq(workspace || File.realpath(checkout))
      expect(metadata["git.checkout.is_custom"]).to eq(scenario[:nested] ? "true" : nil)
      expected_branch = if scenario[:overrides]
        "user-branch"
      elsif scenario[:attached]
        "master"
      elsif matched && !scenario[:release]
        "ci-branch"
      end
      expect(metadata["git.branch"]).to eq(expected_branch)
      expect(metadata["git.tag"]).to eq((matched && scenario[:release]) ? "v1" : nil)
      expected_repository_url = if scenario[:overrides]
        "https://example.com/user.git"
      elsif matched
        canonical_url
      else
        "https://mirror.example.com/repository.git"
      end
      expect(metadata["git.repository_url"]).to eq(expected_repository_url)
    end
  end

  it "clears stale commit details for a different explicit SHA and preserves explicit details" do
    metadata = Datadog::CI::Ext::Environment.tags("DD_GIT_COMMIT_SHA" => "a" * 40,
      "DD_GIT_COMMIT_MESSAGE" => "selected commit")
    expect(metadata["git.commit.sha"]).to eq("a" * 40)
    expect(metadata["git.commit.message"]).to eq("selected commit")
    expect(metadata).not_to have_key("git.commit.author.name")
    expect(metadata).not_to have_key("git.tag")
  end

  it "uses a verified Azure merge revision to recognize a matching detached checkout" do
    tree = git("rev-parse", "HEAD^{tree}")
    side = git("hash-object", "-t", "commit", "-w", "--stdin", input: "tree #{tree}\nparent #{@head}\nauthor Fixture <fixture@example.com> 1700000000 +0000\ncommitter Fixture <fixture@example.com> 1700000000 +0000\n\nSide fixture\n")
    commit = "tree #{tree}\nparent #{@head}\nparent #{side}\nauthor Fixture <fixture@example.com> 1700000000 +0000\ncommitter Fixture <fixture@example.com> 1700000000 +0000\n\nMerge fixture\n"
    merge = git("hash-object", "-t", "commit", "-w", "--stdin", input: commit)
    git("checkout", "--detach", merge)
    metadata = Datadog::CI::Ext::Environment.tags("TF_BUILD" => "true", "BUILD_REASON" => "PullRequest",
      "BUILD_SOURCEBRANCH" => "refs/pull/12/merge", "BUILD_SOURCEVERSION" => merge.upcase,
      "SYSTEM_PULLREQUEST_SOURCECOMMITID" => @head, "SYSTEM_PULLREQUEST_SOURCEBRANCH" => "refs/heads/feature",
      "BUILD_SOURCESDIRECTORY" => @workspace, "BUILD_REPOSITORY_URI" => "https://example.com/project.git")
    expect(metadata).to include("git.commit.sha" => merge, "ci.git.merge_commit_sha" => merge,
      "git.branch" => "feature", "git.repository_url" => "https://example.com/project.git")
  end

  it "keeps Git commands in their initial checkout when the process changes directory" do
    metadata = Datadog::CI::Ext::Environment.tags({})
    tree = git("rev-parse", "HEAD^{tree}")
    nested_commit = "tree #{tree}\nauthor Fixture <fixture@example.com> 1700000000 +0000\ncommitter Fixture <fixture@example.com> 1700000000 +0000\n\nNested checkout\n"
    nested_head = git("hash-object", "-t", "commit", "-w", "--stdin", directory: @nested, input: nested_commit)
    git("update-ref", "refs/heads/master", nested_head, directory: @nested)
    Dir.mktmpdir("packfiles") do |path|
      Dir.chdir(@nested) do
        repository = Datadog::CI::Git::LocalRepository
        expect(repository.root).to eq(metadata["git.checkout.root"])
        expect(repository.git_commits(@head.upcase)).to eq([@head])
        basename = repository.git_generate_packfiles(included_commits: [@head], excluded_commits: [], path: path)
        objects = git("verify-pack", "-v", Dir[File.join(path, "#{basename}*.idx")].first)
        expect(objects).to include("#{@head} commit", "#{tree} tree")
        expect(objects).not_to include(" blob ", nested_head)
      end
    end
  end

  ["GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR"].each do |variable|
    it "preserves relative #{variable} after a directory change" do
      value = (variable == "GIT_WORK_TREE") ? "." : ".git"
      ClimateControl.modify(variable => value) do
        expect(Datadog::CI::Git::LocalRepository.git_commit_sha).to eq(@head)
        Dir.chdir(@nested) do
          expect(Datadog::CI::Git::LocalRepository.git_commit_sha).to eq(@head)
          expect(Datadog::CI::Git::LocalRepository.git_root).to eq(File.realpath(@workspace))
        end
      end
    end
  end

  it "bounds selected history to 1,000 commits and retains an old selected root" do
    stream = +""
    1005.times do
      stream << "commit refs/heads/history\ncommitter Fixture <fixture@example.com> #{Time.now.to_i} +0000\ndata 7\nhistory\n\n"
    end
    git("fast-import", "--quiet", input: stream)
    selected = git("rev-parse", "history")
    commits = Datadog::CI::Git::LocalRepository.git_commits(selected)
    expect(commits.size).to eq(1000)
    expect(commits.first).to eq(selected)
    expect(commits).not_to include(@head)
    expect(Datadog::CI::Git::LocalRepository.git_commits(@head)).to eq([@head])
    objects = Datadog::CI::Git::LocalRepository.git_commits_rev_list(included_commits: [@head], excluded_commits: [])
    expect(objects.split).to include(@head, git("rev-parse", "#{@head}^{tree}"))
    excluded = Datadog::CI::Git::LocalRepository.git_commits_rev_list(included_commits: [@head], excluded_commits: [@head])
    expect(excluded.to_s.split).to be_empty
  end

  it "reads stored metadata without walking an unavailable parent" do
    tree = git("rev-parse", "HEAD^{tree}")
    commit = "tree #{tree}\nparent #{"b" * 40}\nauthor Fixture\tAuthor <fixture@example.com> 1700000000 +0000\ncommitter Fixture <fixture@example.com> 1700000000 +0000\n\nStored metadata\n"
    selected = git("hash-object", "-t", "commit", "-w", "--stdin", input: commit)
    repository = Datadog::CI::Git::LocalRepository
    expect(repository.git_commit_message(selected)).to eq("Stored metadata")
    expect(repository.git_commit_users(selected).first.name).to eq("Fixture\tAuthor")
  end

  it "honors transitive exclusions in the old selected root fallback" do
    tree = git("rev-parse", "HEAD^{tree}")
    commit = "tree #{tree}\nparent #{@head}\nauthor Fixture <fixture@example.com> 1700000000 +0000\ncommitter Fixture <fixture@example.com> 1700000000 +0000\n\nKnown descendant\n"
    descendant = git("hash-object", "-t", "commit", "-w", "--stdin", input: commit)
    objects = Datadog::CI::Git::LocalRepository.git_commits_rev_list(included_commits: [@head], excluded_commits: [descendant])
    expect(objects.to_s.split).to be_empty
  end

  it "selects a clone -o remote after detaching with a backup remote present" do
    checkout = File.join(File.dirname(@workspace), "custom")
    git("clone", "--no-local", "-o", "upstream", @workspace, checkout)
    git("remote", "add", "backup", "https://example.com/backup.git", directory: checkout)
    git("checkout", "--detach", "HEAD", directory: checkout)
    File.open(File.join(checkout, ".git/config"), "a") { |file| file.puts("[feature]\n enabled") }
    Dir.chdir(checkout) do
      repository = Datadog::CI::Git::LocalRepository
      expect(repository.get_remote_name).to eq("upstream")
      expect(repository.git_repository_url).to eq(@workspace)
      File.write(File.join(checkout, ".git/remote settings"), "[clone]\n defaultRemoteName = backup\n")
      git("config", "include.path", "remote settings", directory: checkout)
      expect(repository.get_remote_name).to eq("backup")
      expect(repository.git_repository_url).to eq("https://example.com/backup.git")
    end
  end

  it "does not invent a repository URL or borrow one from CI for a readable no-remote checkout" do
    git("remote", "remove", "origin")
    metadata = Datadog::CI::Ext::Environment.tags("GITHUB_SHA" => "a" * 40,
      "GITHUB_REPOSITORY" => "project/repository", "GITHUB_SERVER_URL" => "https://example.com")
    expect(metadata["git.commit.sha"]).to eq(@head)
    expect(metadata).not_to have_key("git.repository_url")
  end

  it "does not change the caller's environment while extracting PR metadata" do
    env = {"GITHUB_SHA" => @head, "GITHUB_REF" => "refs/pull/12/merge"}.freeze
    expect { Datadog::CI::Ext::Environment.tags(env) }.not_to raise_error
    expect(env.keys).to contain_exactly("GITHUB_SHA", "GITHUB_REF")
  end

  it "does not substitute HEAD when an explicit upload revision is missing" do
    expect(Datadog::CI::Git::LocalRepository.git_commits("a" * 40)).to eq([])
  end
end
