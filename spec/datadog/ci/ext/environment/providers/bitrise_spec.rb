RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Bitrise do
  describe ".tags" do
    include_context "extract tags from environment with given provider and use a subject"

    context "example fixture" do
      let(:env) do
        {
          "BITRISE_BUILD_NUMBER" => "bitrise-pipeline-number",
          "BITRISE_BUILD_SLUG" => "bitrise-pipeline-id",
          "BITRISE_BUILD_URL" => "https://bitrise-build-url.com//",
          "BITRISE_GIT_COMMIT" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "BITRISE_GIT_MESSAGE" => "bitrise-git-commit-message",
          "BITRISE_SOURCE_DIR" => "/foo/bar",
          "BITRISE_TRIGGERED_WORKFLOW_ID" => "bitrise-pipeline-name",
          "GIT_CLONE_COMMIT_HASH" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "GIT_REPOSITORY_URL" => "https://bitrise-build-url.com/repo.git"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "ci.pipeline.id" => "bitrise-pipeline-id",
          "ci.pipeline.name" => "bitrise-pipeline-name",
          "ci.pipeline.number" => "bitrise-pipeline-number",
          "ci.pipeline.url" => "https://bitrise-build-url.com//",
          "ci.provider.name" => "bitrise",
          "ci.workspace_path" => "/foo/bar",
          "git.commit.message" => "bitrise-git-commit-message",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://bitrise-build-url.com/repo.git"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
