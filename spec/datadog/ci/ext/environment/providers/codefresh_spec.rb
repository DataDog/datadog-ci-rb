RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Codefresh do
  describe ".tags" do
    subject(:extracted_tags) do
      ClimateControl.modify(environment_variables) { described_class.new(env).tags }
    end

    let(:env) { {} }
    let(:environment_variables) { {} }

    context "example fixture" do
      let(:env) do
        {
          "CF_BUILD_ID" => "6410367cee516146a4c4c66e",
          "CF_BUILD_URL" => "https://g.codefresh.io/build/6410367cee516146a4c4c66e",
          "CF_PIPELINE_NAME" => "My simple project/Example Java Project Pipeline",
          "CF_STEP_NAME" => "mah-job-name"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "_dd.ci.env_vars" => "{\"CF_BUILD_ID\":\"6410367cee516146a4c4c66e\"}",
          "ci.job.name" => "mah-job-name",
          "ci.pipeline.id" => "6410367cee516146a4c4c66e",
          "ci.pipeline.name" => "My simple project/Example Java Project Pipeline",
          "ci.pipeline.url" => "https://g.codefresh.io/build/6410367cee516146a4c4c66e",
          "ci.provider.name" => "codefresh"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
