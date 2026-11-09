RSpec.describe ::Datadog::CI::Ext::Environment::Providers::LocalGit do
  let(:env) { {} }
  let(:environment_variables) { {} }

  describe "#git_tag" do
    subject(:tag) { described_class.new(env, preferred_tag: preferred_tag).git_tag }

    let(:preferred_tag) { "v1.2.3" }

    before { allow(Datadog::CI::Git::LocalRepository).to receive(:git_tag).and_return(local_tags) }

    {
      nil => nil,
      "" => nil,
      "v1.2.3" => "v1.2.3",
      "latest\nv1.2.3" => "v1.2.3",
      "v2.0.0\nlatest" => "latest"
    }.each do |output, expected|
      context "with local tags #{output.inspect}" do
        let(:local_tags) { output }

        it { is_expected.to eq(expected) }
      end
    end

    context "without a preferred tag" do
      let(:preferred_tag) { nil }
      let(:local_tags) { "v1.2.3\nlatest" }

      it "selects the first tag alphabetically" do
        is_expected.to eq("latest")
      end
    end
  end

  describe "#git_branch" do
    it "treats a detached HEAD as unavailable" do
      allow(Datadog::CI::Git::LocalRepository).to receive(:git_branch).and_return("HEAD")
      expect(described_class.new(env).git_branch).to be_nil
    end
  end

  describe "#tags" do
    include_context "extract environment tags"

    context "example git repository" do
      include_context "with git fixture", "gitdir_with_commit"

      let(:expected_tags) do
        {
          "ci.workspace_path" => "#{Dir.pwd}/spec/support/fixtures/git",
          "git.branch" => "master",
          "git.commit.author.date" => "2011-02-16T13:00:00+00:00",
          "git.commit.author.email" => "bot@friendly.test",
          "git.commit.author.name" => "Friendly bot",
          "git.commit.committer.date" => "2023-10-02T13:52:56+00:00",
          "git.commit.committer.email" => "andrey.marchenko@datadoghq.com",
          "git.commit.committer.name" => "Andrey Marchenko",
          "git.commit.message" => "First commit with ❤️",
          "git.commit.sha" => "c7f893648f656339f62fb7b4d8a6ecdf7d063835",
          "git.repository_url" => "https://datadoghq.com/git/test.git"
        }
      end

      it "matches expected tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end

  describe "#committer" do
    include_context "with git fixture", "gitdir_with_commit"

    subject(:committer_email) do
      ClimateControl.modify(environment_variables) { described_class.new(env).git_commit_committer_email }
    end

    it "returns committer from the latest commit in the repository" do
      is_expected.to eq("andrey.marchenko@datadoghq.com")
    end

    context "when git show -s returns nothing" do
      before do
        allow(Datadog::CI::Utils::Command).to receive(:exec_command).and_return(["", double(success?: true)])
      end

      it "returns nil and does not fail" do
        is_expected.to be_nil
      end
    end
  end
end
