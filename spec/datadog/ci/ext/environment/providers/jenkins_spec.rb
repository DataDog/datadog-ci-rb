RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Jenkins do
  describe ".tags" do
    subject(:extracted_tags) do
      ClimateControl.modify(environment_variables) { described_class.new(env).tags }
    end

    let(:env) { {} }
    let(:environment_variables) { {} }

    context "example fixture" do
      let(:env) do
        {
          "BUILD_NUMBER" => "jenkins-pipeline-number",
          "BUILD_TAG" => "jenkins-pipeline-id",
          "BUILD_URL" => "https://jenkins.com/pipeline",
          "DD_CUSTOM_TRACE_ID" => "jenkins-custom-trace-id",
          "GIT_BRANCH" => "origin/master",
          "GIT_COMMIT" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "GIT_URL_1" => "https://jenkins.com/repo/sample.git",
          "GIT_URL_2" => "https://jenkins.com/repo/otherSample.git",
          "JENKINS_URL" => "jenkins",
          "JOB_NAME" => "jobName/KEY1=VALUE1,KEY2=VALUE2/master",
          "JOB_URL" => "https://jenkins.com/job"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"DD_CUSTOM_TRACE_ID\":\"jenkins-custom-trace-id\"}",
          "ci.pipeline.id" => "jenkins-pipeline-id",
          "ci.pipeline.name" => "jobName",
          "ci.pipeline.number" => "jenkins-pipeline-number",
          "ci.pipeline.url" => "https://jenkins.com/pipeline",
          "ci.provider.name" => "jenkins",
          "git.branch" => "master",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://jenkins.com/repo/sample.git"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end

      context "no git branch info" do
        let(:env) do
          hash = super()
          hash.delete("GIT_BRANCH")
          hash
        end

        let(:expected_tags) do
          hash = super()
          hash.delete("git.branch")
          hash.merge({"ci.pipeline.name" => "jobName/master"})
        end

        it "does not remove branch name from job name" do
          is_expected.to eq(expected_tags)
        end
      end
    end
  end
end
