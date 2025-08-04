RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Buildkite do
  describe ".tags" do
    include_context "extract environment tags"

    context "example fixture" do
      let(:env) do
        {
          "BUILDKITE" => "true",
          "BUILDKITE_BRANCH" => "master",
          "BUILDKITE_BUILD_AUTHOR" => "buildkite-git-commit-author-name",
          "BUILDKITE_BUILD_AUTHOR_EMAIL" => "buildkite-git-commit-author-email@datadoghq.com",
          "BUILDKITE_BUILD_CHECKOUT_PATH" => "/foo/bar",
          "BUILDKITE_BUILD_ID" => "buildkite-pipeline-id",
          "BUILDKITE_BUILD_NUMBER" => "buildkite-pipeline-number",
          "BUILDKITE_BUILD_URL" => "https://buildkite-build-url.com",
          "BUILDKITE_COMMIT" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "BUILDKITE_JOB_ID" => "buildkite-job-id",
          "BUILDKITE_MESSAGE" => "buildkite-git-commit-message",
          "BUILDKITE_PIPELINE_SLUG" => "buildkite-pipeline-name",
          "BUILDKITE_REPO" => "http://hostname.com/repo.git",
          "BUILDKITE_TAG" => "",
          "BUILDKITE_PULL_REQUEST_BASE_BRANCH" => "main"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"BUILDKITE_BUILD_ID\":\"buildkite-pipeline-id\",\"BUILDKITE_JOB_ID\":\"buildkite-job-id\"}",
          "ci.job.id" => "buildkite-job-id",
          "ci.job.url" => "https://buildkite-build-url.com#buildkite-job-id",
          "ci.pipeline.id" => "buildkite-pipeline-id",
          "ci.pipeline.name" => "buildkite-pipeline-name",
          "ci.pipeline.number" => "buildkite-pipeline-number",
          "ci.pipeline.url" => "https://buildkite-build-url.com",
          "ci.provider.name" => "buildkite",
          "ci.workspace_path" => "/foo/bar",
          "git.branch" => "master",
          "git.commit.author.email" => "buildkite-git-commit-author-email@datadoghq.com",
          "git.commit.author.name" => "buildkite-git-commit-author-name",
          "git.commit.message" => "buildkite-git-commit-message",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "http://hostname.com/repo.git",
          "git.pull_request.base_branch" => "main"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
