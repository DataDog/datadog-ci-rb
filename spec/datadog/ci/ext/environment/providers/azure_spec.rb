RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Azure do
  describe ".tags" do
    subject(:extracted_tags) do
      ClimateControl.modify(environment_variables) { described_class.new(env).tags }
    end

    let(:env) { {} }
    let(:environment_variables) { {} }

    context "example fixture" do
      let(:env) do
        {
          "BUILD_BUILDID" => "azure-pipelines-build-id",
          "BUILD_DEFINITIONNAME" => "azure-pipelines-name",
          "BUILD_REPOSITORY_URI" => "https://azure-pipelines-server-uri.com/build.git",
          "BUILD_REQUESTEDFOREMAIL" => "azure-pipelines-commit-author-email@datadoghq.com",
          "BUILD_REQUESTEDFORID" => "azure-pipelines-commit-author",
          "BUILD_SOURCEBRANCH" => "master",
          "BUILD_SOURCESDIRECTORY" => "/foo/bar",
          "BUILD_SOURCEVERSION" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "BUILD_SOURCEVERSIONMESSAGE" => "azure-pipelines-commit-message",
          "SYSTEM_JOBID" => "azure-pipelines-job-id",
          "SYSTEM_TASKINSTANCEID" => "azure-pipelines-task-id",
          "SYSTEM_TEAMFOUNDATIONSERVERURI" => "https://azure-pipelines-server-uri.com/",
          "SYSTEM_TEAMPROJECTID" => "azure-pipelines-project-id",
          "SYSTEM_STAGEDISPLAYNAME" => "azure-stage",
          "TF_BUILD" => "True",
          "HOME" => "/not-my-home",
          "USERPROFILE" => "/not-my-home"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"SYSTEM_TEAMPROJECTID\":\"azure-pipelines-project-id\",\"BUILD_BUILDID\":\"azure-pipelines-build-id\",\"SYSTEM_JOBID\":\"azure-pipelines-job-id\"}",
          "ci.job.url" => "https://azure-pipelines-server-uri.com/azure-pipelines-project-id/_build/results?buildId=azure-pipelines-build-id&view=logs&j=azure-pipelines-job-id&t=azure-pipelines-task-id",
          "ci.pipeline.id" => "azure-pipelines-build-id",
          "ci.pipeline.name" => "azure-pipelines-name",
          "ci.pipeline.number" => "azure-pipelines-build-id",
          "ci.pipeline.url" => "https://azure-pipelines-server-uri.com/azure-pipelines-project-id/_build/results?buildId=azure-pipelines-build-id",
          "ci.provider.name" => "azurepipelines",
          "ci.stage.name" => "azure-stage",
          "ci.workspace_path" => "/foo/bar",
          "git.branch" => "master",
          "git.commit.author.email" => "azure-pipelines-commit-author-email@datadoghq.com",
          "git.commit.author.name" => "azure-pipelines-commit-author",
          "git.commit.message" => "azure-pipelines-commit-message",
          "git.commit.sha" => "b9f0fb3fdbb94c9d24b2c75b49663122a529e123",
          "git.repository_url" => "https://azure-pipelines-server-uri.com/build.git"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end

      context "when pipeline URL cannot be defined" do
        let(:env) do
          hash = super()
          hash.delete("BUILD_BUILDID")
          hash
        end

        let(:expected_tags) do
          hash = super()
          hash["_dd.ci.env_vars"] = "{\"SYSTEM_TEAMPROJECTID\":\"azure-pipelines-project-id\",\"BUILD_BUILDID\":null,\"SYSTEM_JOBID\":\"azure-pipelines-job-id\"}"
          ["ci.pipeline.id", "ci.pipeline.number", "ci.pipeline.url", "ci.job.url"].each do |key|
            hash.delete(key)
          end
          hash
        end

        it "omits URLs" do
          is_expected.to eq(expected_tags)
        end
      end
    end
  end
end
