RSpec.describe ::Datadog::CI::Ext::Environment::Providers::LocalGit do
  let(:env) { {} }
  let(:environment_variables) { {} }

  describe "#tags" do
    include_context "extract tags from environment with given provider and use a subject"

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
        allow(Open3).to receive(:capture2e).and_return(["", double(success?: true)])
      end

      it "returns nil and does not fail" do
        is_expected.to be_nil
      end
    end
  end
end
