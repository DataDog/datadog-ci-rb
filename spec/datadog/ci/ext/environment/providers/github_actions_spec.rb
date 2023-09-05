RSpec.describe ::Datadog::CI::Ext::Environment::Providers::GithubActions do
  describe ".tags" do
    subject(:extracted_tags) do
      ClimateControl.modify(environment_variables) { described_class.new(env).tags }
    end

    let(:env) { {} }
    let(:environment_variables) { {} }

    context "example fixture" do
      let(:env) do
        {
          "GITHUB_ACTION" => "run",
          "GITHUB_JOB" => "github-job-name",
          "GITHUB_REF" => "master",
          "GITHUB_REPOSITORY" => "ghactions-repo",
          "GITHUB_RUN_ID" => "ghactions-pipeline-id",
          "GITHUB_RUN_NUMBER" => "ghactions-pipeline-number",
          "GITHUB_SERVER_URL" => "https://ghenterprise.com",
          "GITHUB_SHA" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "GITHUB_WORKFLOW" => "ghactions-pipeline-name",
          "GITHUB_WORKSPACE" => "/foo/bar"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"GITHUB_SERVER_URL\":\"https://ghenterprise.com\",\"GITHUB_REPOSITORY\":\"ghactions-repo\",\"GITHUB_RUN_ID\":\"ghactions-pipeline-id\"}",
          "ci.job.name" => "github-job-name",
          "ci.job.url" => "https://ghenterprise.com/ghactions-repo/commit/b9f0fb3fdbb94c9d24b2c75b49663122a529e123/checks",
          "ci.pipeline.id" => "ghactions-pipeline-id",
          "ci.pipeline.name" => "ghactions-pipeline-name",
          "ci.pipeline.number" => "ghactions-pipeline-number",
          "ci.pipeline.url" => "https://ghenterprise.com/ghactions-repo/actions/runs/ghactions-pipeline-id",
          "ci.provider.name" => "github",
          "ci.workspace_path" => "/foo/bar",
          "git.branch" => "master",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://ghenterprise.com/ghactions-repo.git"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
