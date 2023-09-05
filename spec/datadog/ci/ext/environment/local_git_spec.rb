RSpec.describe ::Datadog::CI::Ext::Environment::LocalGit do
  let(:env) { {} }
  let(:environment_variables) { {} }

  describe "#tags" do
    subject(:extracted_tags) do
      ClimateControl.modify(environment_variables) { described_class.new(env).tags }
    end

    context "example git repository" do
      include_context "with git fixture", "gitdir_with_commit"

      let(:expected_tags) do
        {
          "ci.workspace_path" => "#{Dir.pwd}/spec/support/fixtures/git",
          "git.branch" => "master",
          "git.commit.author.date" => "2011-02-16T13:00:00+00:00",
          "git.commit.author.email" => "bot@friendly.test",
          "git.commit.author.name" => "Friendly bot",
          "git.commit.committer.date" => "2021-06-17T18:35:10+00:00",
          "git.commit.committer.email" => "marco.costa@datadoghq.com",
          "git.commit.committer.name" => "Marco Costa",
          "git.commit.message" => "First commit!",
          "git.commit.sha" => "9322ca1d57975b49b8c00b449d21b06660ce8b5b",
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
      ClimateControl.modify(environment_variables) { described_class.new(env).tags["git.commit.committer.email"] }
    end

    it "returns committer from the latest commit in the repository" do
      is_expected.to eq("marco.costa@datadoghq.com")
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
