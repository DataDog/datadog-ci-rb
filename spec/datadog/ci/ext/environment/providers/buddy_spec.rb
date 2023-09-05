RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Buddy do
  describe ".tags" do
    subject(:extracted_tags) do
      ClimateControl.modify(environment_variables) { described_class.new(env).tags }
    end

    let(:env) { {} }
    let(:environment_variables) { {} }

    context "example fixture" do
      let(:env) do
        {
          "BUDDY" => "true",
          "BUDDY_EXECUTION_BRANCH" => "master",
          "BUDDY_EXECUTION_ID" => "buddy-execution-id",
          "BUDDY_EXECUTION_REVISION" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "BUDDY_EXECUTION_REVISION_COMMITTER_EMAIL" => "mikebenson@buddy.works",
          "BUDDY_EXECUTION_REVISION_COMMITTER_NAME" => "Mike Benson",
          "BUDDY_EXECUTION_REVISION_MESSAGE" => "Create buddy.yml",
          "BUDDY_EXECUTION_TAG" => "v1.0",
          "BUDDY_EXECUTION_URL" => "https://app.buddy.works/myworkspace/my-project/pipelines/pipeline/456/execution/5d9dc42c422f5a268b389d08",
          "BUDDY_PIPELINE_ID" => "456",
          "BUDDY_PIPELINE_NAME" => "Deploy to Production",
          "BUDDY_SCM_URL" => "https://github.com/buddyworks/my-project.git"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "ci.pipeline.id" => "456/buddy-execution-id",
          "ci.pipeline.name" => "Deploy to Production",
          "ci.pipeline.number" => "buddy-execution-id",
          "ci.pipeline.url" => "https://app.buddy.works/myworkspace/my-project/pipelines/pipeline/456/execution/5d9dc42c422f5a268b389d08",
          "ci.provider.name" => "buddy",
          "git.branch" => "master",
          "git.commit.committer.email" => "mikebenson@buddy.works",
          "git.commit.committer.name" => "Mike Benson",
          "git.commit.message" => "Create buddy.yml",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://github.com/buddyworks/my-project.git",
          "git.tag" => "v1.0"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
