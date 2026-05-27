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
      # DD_GIT_REPOSITORY_URL and DD_GIT_COMMIT_SHA must also be set in actual ENV because
      # the provider reads them via Datadog.configuration.git when the config DSL is available.
      let(:environment_variables) do
        super().merge(
          "HOME" => env["HOME"],
          Datadog::CI::Ext::Git::ENV_REPOSITORY_URL => env[Datadog::CI::Ext::Git::ENV_REPOSITORY_URL],
          Datadog::CI::Ext::Git::ENV_COMMIT_SHA => env[Datadog::CI::Ext::Git::ENV_COMMIT_SHA]
        )
      end

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

    context "git settings via Datadog configuration DSL" do
      context "when git settings are available and set programmatically",
        if: Datadog.configuration.respond_to?(:git) do
        before do
          Datadog.configure do |c|
            c.git.repository_url = "https://programmatic.example.com/repo.git"
            c.git.commit_sha = "abc123programmatic"
          end
        end

        let(:env) { {} }

        it "uses the programmatically configured repository_url" do
          expect(extracted_tags).to include("git.repository_url" => "https://programmatic.example.com/repo.git")
        end

        it "uses the programmatically configured commit_sha" do
          expect(extracted_tags).to include("git.commit.sha" => "abc123programmatic")
        end
      end

      context "when Datadog configuration does not support git settings (older dd-trace-rb)" do
        let(:config_without_git) { double("datadog_config") }

        before do
          allow(config_without_git).to receive(:respond_to?).with(:git).and_return(false)
          allow(::Datadog).to receive(:configuration).and_return(config_without_git)
        end

        let(:env) do
          {
            Datadog::CI::Ext::Git::ENV_REPOSITORY_URL => "https://env-fallback.example.com/repo.git",
            Datadog::CI::Ext::Git::ENV_COMMIT_SHA => "sha-from-env-fallback"
          }
        end

        it "falls back to DD_GIT_REPOSITORY_URL environment variable" do
          expect(extracted_tags).to include("git.repository_url" => "https://env-fallback.example.com/repo.git")
        end

        it "falls back to DD_GIT_COMMIT_SHA environment variable" do
          expect(extracted_tags).to include("git.commit.sha" => "sha-from-env-fallback")
        end
      end
    end
  end
end
