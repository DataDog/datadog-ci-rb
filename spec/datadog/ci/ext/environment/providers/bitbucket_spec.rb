RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Bitbucket do
  describe ".tags" do
    include_context "extract environment tags"

    context "example fixture" do
      let(:env) do
        {
          "BITBUCKET_BRANCH" => "master",
          "BITBUCKET_BUILD_NUMBER" => "bitbucket-build-num",
          "BITBUCKET_CLONE_DIR" => "/foo/bar",
          "BITBUCKET_COMMIT" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "BITBUCKET_GIT_HTTP_ORIGIN" => "https://bitbucket-repo-url.com/repo.git",
          "BITBUCKET_PIPELINE_UUID" => "{bitbucket-uuid}",
          "BITBUCKET_REPO_FULL_NAME" => "bitbucket-repo",
          "BITBUCKET_PR_DESTINATION_BRANCH" => "main"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "ci.job.url" => "https://bitbucket.org/bitbucket-repo/addon/pipelines/home#!/results/bitbucket-build-num",
          "ci.pipeline.id" => "bitbucket-uuid",
          "ci.pipeline.name" => "bitbucket-repo",
          "ci.pipeline.number" => "bitbucket-build-num",
          "ci.pipeline.url" => "https://bitbucket.org/bitbucket-repo/addon/pipelines/home#!/results/bitbucket-build-num",
          "ci.provider.name" => "bitbucket",
          "ci.workspace_path" => "/foo/bar",
          "git.branch" => "master",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://bitbucket-repo-url.com/repo.git",
          "git.pull_request.base_branch" => "main"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end

      context "when no BITBUCKET_PIPELINE_UUID provided" do
        let(:env) do
          hash = super()
          hash.delete("BITBUCKET_PIPELINE_UUID")
          hash
        end

        let(:expected_tags) do
          hash = super()
          hash.delete("ci.pipeline.id")
          hash
        end

        it "omits pipeline_id" do
          is_expected.to eq(expected_tags)
        end
      end
    end
  end
end
