RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Gitlab do
  describe ".tags" do
    include_context "extract environment tags"

    context "example fixture" do
      let(:env) do
        {
          "CI_COMMIT_AUTHOR" => "John Doe <john@doe.com>",
          "CI_COMMIT_MESSAGE" => "gitlab-git-commit-message",
          "CI_COMMIT_REF_NAME" => "origin/master",
          "CI_COMMIT_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "CI_COMMIT_TIMESTAMP" => "2021-07-21T11:43:07-04:00",
          "CI_JOB_ID" => "gitlab-job-id",
          "CI_JOB_NAME" => "gitlab-job-name",
          "CI_JOB_STAGE" => "gitlab-stage-name",
          "CI_JOB_URL" => "https://gitlab.com/job",
          "CI_PIPELINE_ID" => "gitlab-pipeline-id",
          "CI_PIPELINE_IID" => "gitlab-pipeline-number",
          "CI_PIPELINE_URL" => "https://foo/repo/-/pipelines/1234",
          "CI_PROJECT_DIR" => "foo/bar",
          "CI_PROJECT_PATH" => "gitlab-pipeline-name",
          "CI_PROJECT_URL" => "https://gitlab.com/repo",
          "CI_REPOSITORY_URL" => "https://gitlab.com/repo/myrepo.git",
          "GITLAB_CI" => "gitlab"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"CI_PROJECT_URL\":\"https://gitlab.com/repo\",\"CI_PIPELINE_ID\":\"gitlab-pipeline-id\",\"CI_JOB_ID\":\"gitlab-job-id\"}",
          "ci.job.name" => "gitlab-job-name",
          "ci.job.url" => "https://gitlab.com/job",
          "ci.pipeline.id" => "gitlab-pipeline-id",
          "ci.pipeline.name" => "gitlab-pipeline-name",
          "ci.pipeline.number" => "gitlab-pipeline-number",
          "ci.pipeline.url" => "https://foo/repo/-/pipelines/1234",
          "ci.provider.name" => "gitlab",
          "ci.stage.name" => "gitlab-stage-name",
          "ci.workspace_path" => "foo/bar",
          "git.branch" => "master",
          "git.commit.author.date" => "2021-07-21T11:43:07-04:00",
          "git.commit.author.email" => "john@doe.com",
          "git.commit.author.name" => "John Doe",
          "git.commit.message" => "gitlab-git-commit-message",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://gitlab.com/repo/myrepo.git"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end

      context "when CI_COMMIT_AUTHOR is malformed" do
        context "no < symbol" do
          let(:env) do
            super().merge({"CI_COMMIT_AUTHOR" => "John Doe john@doe.com>"})
          end

          let(:expected_tags) do
            hash = super()
            hash.delete("git.commit.author.name")
            hash.merge({"git.commit.author.email" => "John Doe john@doe.com>"})
          end

          it "puts CI_COMMIT_AUTHOR under git.commit.author.email" do
            is_expected.to eq(expected_tags)
          end
        end
      end
    end
  end

  describe "#additional_tags" do
    let(:base_env) do
      {
        "GITLAB_CI" => "gitlab",
        "CI_MERGE_REQUEST_TARGET_BRANCH_NAME" => "main",
        "CI_MERGE_REQUEST_TARGET_BRANCH_SHA" => "abc123",
        "CI_MERGE_REQUEST_SOURCE_BRANCH_SHA" => "def456"
      }
    end

    subject { described_class.new(env).additional_tags }

    context "when all relevant variables are present" do
      let(:env) { base_env }
      it "returns all expected tags" do
        expect(subject).to eq({
          Datadog::CI::Ext::Git::TAG_PULL_REQUEST_BASE_BRANCH => "main",
          Datadog::CI::Ext::Git::TAG_PULL_REQUEST_BASE_BRANCH_SHA => "abc123",
          Datadog::CI::Ext::Git::TAG_COMMIT_HEAD_SHA => "def456"
        })
      end
    end

    context "when only base branch is present" do
      let(:env) { base_env.merge("CI_MERGE_REQUEST_TARGET_BRANCH_SHA" => nil, "CI_MERGE_REQUEST_SOURCE_BRANCH_SHA" => nil) }
      it "returns only the base branch tag" do
        expect(subject).to eq({
          Datadog::CI::Ext::Git::TAG_PULL_REQUEST_BASE_BRANCH => "main"
        })
      end
    end

    context "when base branch is missing" do
      let(:env) { base_env.merge("CI_MERGE_REQUEST_TARGET_BRANCH_NAME" => nil) }
      it "returns an empty hash" do
        expect(subject).to eq({})
      end
    end

    context "when base branch is empty" do
      let(:env) { base_env.merge("CI_MERGE_REQUEST_TARGET_BRANCH_NAME" => "") }
      it "returns an empty hash" do
        expect(subject).to eq({})
      end
    end
  end
end
