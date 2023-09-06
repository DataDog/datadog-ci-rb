RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Travis do
  describe ".tags" do
    include_context "extract tags from environment with given provider and use a subject"

    context "example fixture" do
      let(:env) do
        {
          "TRAVIS" => "travisCI",
          "TRAVIS_BRANCH" => "origin/tags/0.1.0",
          "TRAVIS_BUILD_DIR" => "/foo/bar",
          "TRAVIS_BUILD_ID" => "travis-pipeline-id",
          "TRAVIS_BUILD_NUMBER" => "travis-pipeline-number",
          "TRAVIS_BUILD_WEB_URL" => "https://travisci.com/pipeline",
          "TRAVIS_COMMIT" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "TRAVIS_COMMIT_MESSAGE" => "travis-commit-message",
          "TRAVIS_JOB_WEB_URL" => "https://travisci.com/job",
          "TRAVIS_REPO_SLUG" => "user/repo",
          "TRAVIS_TAG" => "origin/tags/0.1.0"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "ci.job.url" => "https://travisci.com/job",
          "ci.pipeline.id" => "travis-pipeline-id",
          "ci.pipeline.name" => "user/repo",
          "ci.pipeline.number" => "travis-pipeline-number",
          "ci.pipeline.url" => "https://travisci.com/pipeline",
          "ci.provider.name" => "travisci",
          "ci.workspace_path" => "/foo/bar",
          "git.commit.message" => "travis-commit-message",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://github.com/user/repo.git",
          "git.tag" => "0.1.0"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
