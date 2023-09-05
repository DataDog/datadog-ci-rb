RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Appveyor do
  describe ".tags" do
    subject(:extracted_tags) do
      ClimateControl.modify(environment_variables) { described_class.new(env).tags }
    end

    let(:env) { {} }
    let(:environment_variables) { {} }

    context "example fixture" do
      let(:env) do
        {
          "APPVEYOR" => "true",
          "APPVEYOR_BUILD_FOLDER" => "/foo/bar",
          "APPVEYOR_BUILD_ID" => "appveyor-build-id",
          "APPVEYOR_BUILD_NUMBER" => "appveyor-pipeline-number",
          "APPVEYOR_REPO_BRANCH" => "master",
          "APPVEYOR_REPO_COMMIT" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "APPVEYOR_REPO_COMMIT_AUTHOR" => "appveyor-commit-author-name",
          "APPVEYOR_REPO_COMMIT_AUTHOR_EMAIL" => "appveyor-commit-author-email@datadoghq.com",
          "APPVEYOR_REPO_COMMIT_MESSAGE" => "appveyor-commit-message",
          "APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED" => "appveyor-commit-message-extended",
          "APPVEYOR_REPO_NAME" => "appveyor-repo-name",
          "APPVEYOR_REPO_PROVIDER" => "github"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "ci.job.url" => "https://ci.appveyor.com/project/appveyor-repo-name/builds/appveyor-build-id",
          "ci.pipeline.id" => "appveyor-build-id",
          "ci.pipeline.name" => "appveyor-repo-name",
          "ci.pipeline.number" => "appveyor-pipeline-number",
          "ci.pipeline.url" => "https://ci.appveyor.com/project/appveyor-repo-name/builds/appveyor-build-id",
          "ci.provider.name" => "appveyor",
          "ci.workspace_path" => "/foo/bar",
          "git.branch" => "master",
          "git.commit.author.email" => "appveyor-commit-author-email@datadoghq.com",
          "git.commit.author.name" => "appveyor-commit-author-name",
          "git.commit.message" => "appveyor-commit-message\nappveyor-commit-message-extended",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://github.com/appveyor-repo-name.git"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end

      context "when commit message is not provided" do
        let(:env) do
          hash = super()
          hash.delete("APPVEYOR_REPO_COMMIT_MESSAGE")
          hash
        end

        let(:expected_tags) do
          hash = super()
          hash.delete("git.commit.message")
          hash
        end

        it "omits git.commit.message" do
          is_expected.to eq(expected_tags)
        end
      end

      context "when extended commit message is not provided" do
        let(:env) do
          hash = super()
          hash.delete("APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED")
          hash
        end

        it "does not append extended commit message" do
          is_expected.to eq(expected_tags.merge({"git.commit.message" => "appveyor-commit-message"}))
        end
      end
    end
  end
end
