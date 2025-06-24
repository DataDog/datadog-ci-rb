RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Drone do
  describe ".handles?" do
    context "when DRONE environment variable is set" do
      it "returns true" do
        expect(described_class.handles?({"DRONE" => "true"})).to be true
      end
    end

    context "when DRONE environment variable is not set" do
      it "returns false" do
        expect(described_class.handles?({})).to be false
      end
    end
  end

  describe ".tags" do
    include_context "extract environment tags"

    context "without pull request" do
      let(:env) do
        {
          "CI" => "true",
          "DRONE" => "true",
          "DRONE_BRANCH" => "master",
          "DRONE_BUILD_LINK" => "https://drone.company.com/octocat/hello-world/42",
          "DRONE_BUILD_NUMBER" => "build-number",
          "DRONE_COMMIT_AUTHOR_EMAIL" => "octocat@github.com",
          "DRONE_COMMIT_AUTHOR_NAME" => "The Octocat",
          "DRONE_COMMIT_MESSAGE" => "Updated README.md",
          "DRONE_COMMIT_SHA" => "bcdd4bf0245c82c060407b3b24b9b87301d15ac1",
          "DRONE_GIT_HTTP_URL" => "https://github.com/octocat/hello-world.git",
          "DRONE_STAGE_NAME" => "build",
          "DRONE_STEP_NAME" => "build_backend",
          "DRONE_TAG" => "v1.0.0",
          "DRONE_WORKSPACE" => "/foo/bar/jenkins/hello-world-job"
        }
      end

      let(:expected_tags) do
        {
          "ci.job.name" => "build_backend",
          "ci.pipeline.number" => "build-number",
          "ci.pipeline.url" => "https://drone.company.com/octocat/hello-world/42",
          "ci.provider.name" => "drone",
          "ci.stage.name" => "build",
          "ci.workspace_path" => "/foo/bar/jenkins/hello-world-job",
          "git.branch" => "master",
          "git.commit.author.email" => "octocat@github.com",
          "git.commit.author.name" => "The Octocat",
          "git.commit.message" => "Updated README.md",
          "git.commit.sha" => "bcdd4bf0245c82c060407b3b24b9b87301d15ac1",
          "git.repository_url" => "https://github.com/octocat/hello-world.git",
          "git.tag" => "v1.0.0"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end

    context "with pull request" do
      let(:env) do
        {
          "CI" => "true",
          "DRONE" => "true",
          "DRONE_BRANCH" => "master",
          "DRONE_BUILD_LINK" => "https://drone.company.com/octocat/hello-world/42",
          "DRONE_BUILD_NUMBER" => "build-number",
          "DRONE_COMMIT_AUTHOR_EMAIL" => "octocat@github.com",
          "DRONE_COMMIT_AUTHOR_NAME" => "The Octocat",
          "DRONE_COMMIT_MESSAGE" => "Updated README.md",
          "DRONE_COMMIT_SHA" => "bcdd4bf0245c82c060407b3b24b9b87301d15ac1",
          "DRONE_GIT_HTTP_URL" => "https://github.com/octocat/hello-world.git",
          "DRONE_PULL_REQUEST" => "42",
          "DRONE_STAGE_NAME" => "build",
          "DRONE_STEP_NAME" => "build_backend",
          "DRONE_TAG" => "v1.0.0",
          "DRONE_TARGET_BRANCH" => "target-branch",
          "DRONE_WORKSPACE" => "/foo/bar/jenkins/hello-world-job"
        }
      end

      let(:expected_tags) do
        {
          "ci.job.name" => "build_backend",
          "ci.pipeline.number" => "build-number",
          "ci.pipeline.url" => "https://drone.company.com/octocat/hello-world/42",
          "ci.provider.name" => "drone",
          "ci.stage.name" => "build",
          "ci.workspace_path" => "/foo/bar/jenkins/hello-world-job",
          "git.branch" => "master",
          "git.commit.author.email" => "octocat@github.com",
          "git.commit.author.name" => "The Octocat",
          "git.commit.message" => "Updated README.md",
          "git.commit.sha" => "bcdd4bf0245c82c060407b3b24b9b87301d15ac1",
          "git.pull_request.base_branch" => "target-branch",
          "git.repository_url" => "https://github.com/octocat/hello-world.git",
          "git.tag" => "v1.0.0",
          "pr.number" => "42"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end

    context "with minimal environment" do
      let(:env) do
        {
          "DRONE" => "true"
        }
      end

      let(:expected_tags) do
        {
          "ci.provider.name" => "drone"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end

  describe "individual methods" do
    let(:provider) { described_class.new(env) }

    describe "#provider_name" do
      let(:env) { {"DRONE" => "true"} }

      it "returns 'drone'" do
        expect(provider.provider_name).to eq("drone")
      end
    end

    describe "#job_name" do
      context "when DRONE_STEP_NAME is set" do
        let(:env) { {"DRONE_STEP_NAME" => "build_backend"} }

        it "returns the step name" do
          expect(provider.job_name).to eq("build_backend")
        end
      end

      context "when DRONE_STEP_NAME is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.job_name).to be_nil
        end
      end
    end

    describe "#pipeline_number" do
      context "when DRONE_BUILD_NUMBER is set" do
        let(:env) { {"DRONE_BUILD_NUMBER" => "build-123"} }

        it "returns the build number" do
          expect(provider.pipeline_number).to eq("build-123")
        end
      end

      context "when DRONE_BUILD_NUMBER is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.pipeline_number).to be_nil
        end
      end
    end

    describe "#pipeline_url" do
      context "when DRONE_BUILD_LINK is set" do
        let(:env) { {"DRONE_BUILD_LINK" => "https://drone.company.com/build/123"} }

        it "returns the build link" do
          expect(provider.pipeline_url).to eq("https://drone.company.com/build/123")
        end
      end

      context "when DRONE_BUILD_LINK is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.pipeline_url).to be_nil
        end
      end
    end

    describe "#stage_name" do
      context "when DRONE_STAGE_NAME is set" do
        let(:env) { {"DRONE_STAGE_NAME" => "build"} }

        it "returns the stage name" do
          expect(provider.stage_name).to eq("build")
        end
      end

      context "when DRONE_STAGE_NAME is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.stage_name).to be_nil
        end
      end
    end

    describe "#workspace_path" do
      context "when DRONE_WORKSPACE is set" do
        let(:env) { {"DRONE_WORKSPACE" => "/foo/bar/workspace"} }

        it "returns the workspace path" do
          expect(provider.workspace_path).to eq("/foo/bar/workspace")
        end
      end

      context "when DRONE_WORKSPACE is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.workspace_path).to be_nil
        end
      end
    end

    describe "#git_repository_url" do
      context "when DRONE_GIT_HTTP_URL is set" do
        let(:env) { {"DRONE_GIT_HTTP_URL" => "https://github.com/user/repo.git"} }

        it "returns the repository URL" do
          expect(provider.git_repository_url).to eq("https://github.com/user/repo.git")
        end
      end

      context "when DRONE_GIT_HTTP_URL is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.git_repository_url).to be_nil
        end
      end
    end

    describe "#git_commit_sha" do
      context "when DRONE_COMMIT_SHA is set" do
        let(:env) { {"DRONE_COMMIT_SHA" => "abc123"} }

        it "returns the commit SHA" do
          expect(provider.git_commit_sha).to eq("abc123")
        end
      end

      context "when DRONE_COMMIT_SHA is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.git_commit_sha).to be_nil
        end
      end
    end

    describe "#git_branch" do
      context "when DRONE_BRANCH is set" do
        let(:env) { {"DRONE_BRANCH" => "main"} }

        it "returns the branch name" do
          expect(provider.git_branch).to eq("main")
        end
      end

      context "when DRONE_BRANCH is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.git_branch).to be_nil
        end
      end
    end

    describe "#git_tag" do
      context "when DRONE_TAG is set" do
        let(:env) { {"DRONE_TAG" => "v1.0.0"} }

        it "returns the tag name" do
          expect(provider.git_tag).to eq("v1.0.0")
        end
      end

      context "when DRONE_TAG is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.git_tag).to be_nil
        end
      end
    end

    describe "#git_commit_author_name" do
      context "when DRONE_COMMIT_AUTHOR_NAME is set" do
        let(:env) { {"DRONE_COMMIT_AUTHOR_NAME" => "John Doe"} }

        it "returns the commit author name" do
          expect(provider.git_commit_author_name).to eq("John Doe")
        end
      end

      context "when DRONE_COMMIT_AUTHOR_NAME is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.git_commit_author_name).to be_nil
        end
      end
    end

    describe "#git_commit_author_email" do
      context "when DRONE_COMMIT_AUTHOR_EMAIL is set" do
        let(:env) { {"DRONE_COMMIT_AUTHOR_EMAIL" => "john@example.com"} }

        it "returns the commit author email" do
          expect(provider.git_commit_author_email).to eq("john@example.com")
        end
      end

      context "when DRONE_COMMIT_AUTHOR_EMAIL is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.git_commit_author_email).to be_nil
        end
      end
    end

    describe "#git_commit_message" do
      context "when DRONE_COMMIT_MESSAGE is set" do
        let(:env) { {"DRONE_COMMIT_MESSAGE" => "Fix bug"} }

        it "returns the commit message" do
          expect(provider.git_commit_message).to eq("Fix bug")
        end
      end

      context "when DRONE_COMMIT_MESSAGE is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.git_commit_message).to be_nil
        end
      end
    end

    describe "#git_pull_request_base_branch" do
      context "when DRONE_TARGET_BRANCH is set" do
        let(:env) { {"DRONE_TARGET_BRANCH" => "main"} }

        it "returns the target branch" do
          expect(provider.git_pull_request_base_branch).to eq("main")
        end
      end

      context "when DRONE_TARGET_BRANCH is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.git_pull_request_base_branch).to be_nil
        end
      end
    end

    describe "#pr_number" do
      context "when DRONE_PULL_REQUEST is set" do
        let(:env) { {"DRONE_PULL_REQUEST" => "42"} }

        it "returns the pull request number" do
          expect(provider.pr_number).to eq("42")
        end
      end

      context "when DRONE_PULL_REQUEST is not set" do
        let(:env) { {} }

        it "returns nil" do
          expect(provider.pr_number).to be_nil
        end
      end
    end
  end
end
