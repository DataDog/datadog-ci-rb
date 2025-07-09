RSpec.describe ::Datadog::CI::Ext::Environment::Providers::UserDefinedTags do
  describe ".tags" do
    include_context "extract environment tags"

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
          "DD_GIT_REPOSITORY_URL" => "git@github.com:DataDog/userrepo.git",
          "DD_GIT_PULL_REQUEST_BASE_BRANCH" => "usersupplied-pullrequest-base-branch",
          "DD_GIT_PULL_REQUEST_BASE_BRANCH_SHA" => "usersupplied-pullrequest-base-branch-sha",
          "DD_GIT_COMMIT_HEAD_SHA" => "usersupplied-commit-head-sha"
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
          "git.repository_url" => "git@github.com:DataDog/userrepo.git",
          "git.pull_request.base_branch" => "usersupplied-pullrequest-base-branch",
          "git.pull_request.base_branch_sha" => "usersupplied-pullrequest-base-branch-sha",
          "git.commit.head.sha" => "usersupplied-commit-head-sha"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
