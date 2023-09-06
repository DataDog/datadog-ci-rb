RSpec.describe ::Datadog::CI::Ext::Environment::Providers::UserDefinedTags do
  describe ".tags" do
    include_context "extract tags from environment with given provider and use a subject"

    context "example fixture" do
      let(:env) do
        {
          "DD_GIT_BRANCH" => "usersupplied-branch",
          "DD_GIT_COMMIT_AUTHOR_DATE" => "usersupplied-authordate",
          "DD_GIT_COMMIT_AUTHOR_EMAIL" => "usersupplied-authoremail",
          "DD_GIT_COMMIT_AUTHOR_NAME" => "usersupplied-authorname",
          "DD_GIT_COMMIT_COMMITTER_DATE" => "usersupplied-comitterdate",
          "DD_GIT_COMMIT_COMMITTER_EMAIL" => "usersupplied-comitteremail",
          "DD_GIT_COMMIT_COMMITTER_NAME" => "usersupplied-comittername",
          "DD_GIT_COMMIT_MESSAGE" => "usersupplied-message",
          "DD_GIT_COMMIT_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "DD_GIT_REPOSITORY_URL" => "git@github.com:DataDog/userrepo.git"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "git.branch" => "usersupplied-branch",
          "git.commit.author.date" => "usersupplied-authordate",
          "git.commit.author.email" => "usersupplied-authoremail",
          "git.commit.author.name" => "usersupplied-authorname",
          "git.commit.committer.date" => "usersupplied-comitterdate",
          "git.commit.committer.email" => "usersupplied-comitteremail",
          "git.commit.committer.name" => "usersupplied-comittername",
          "git.commit.message" => "usersupplied-message",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "git@github.com:DataDog/userrepo.git"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
