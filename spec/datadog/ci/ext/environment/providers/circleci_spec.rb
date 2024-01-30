RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Circleci do
  describe ".tags" do
    include_context "extract environment tags"

    context "example fixture" do
      let(:env) do
        {
          "CIRCLECI" => "circleCI",
          "CIRCLE_BRANCH" => "origin/master",
          "CIRCLE_BUILD_NUM" => "circleci-pipeline-number",
          "CIRCLE_BUILD_URL" => "https://circleci-build-url.com/",
          "CIRCLE_JOB" => "circleci-job-name",
          "CIRCLE_PROJECT_REPONAME" => "circleci-pipeline-name",
          "CIRCLE_REPOSITORY_URL" => "https://circleci-build-url.com/repo.git",
          "CIRCLE_SHA1" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "CIRCLE_WORKFLOW_ID" => "circleci-pipeline-id",
          "CIRCLE_WORKING_DIRECTORY" => "/foo/bar"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"CIRCLE_WORKFLOW_ID\":\"circleci-pipeline-id\",\"CIRCLE_BUILD_NUM\":\"circleci-pipeline-number\"}",
          "ci.job.name" => "circleci-job-name",
          "ci.job.url" => "https://circleci-build-url.com/",
          "ci.pipeline.id" => "circleci-pipeline-id",
          "ci.pipeline.name" => "circleci-pipeline-name",
          "ci.pipeline.url" => "https://app.circleci.com/pipelines/workflows/circleci-pipeline-id",
          "ci.provider.name" => "circleci",
          "ci.workspace_path" => "/foo/bar",
          "git.branch" => "master",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://circleci-build-url.com/repo.git"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
