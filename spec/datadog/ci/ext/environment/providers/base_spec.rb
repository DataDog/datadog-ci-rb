RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Base do
  describe ".tags" do
    include_context "extract environment tags"

    context "example fixture" do
      let(:env) do
        {
          "BUILD_URL" => "https://build.io/build/34432432",
          "PIPELINE_NAME" => "My simple project"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) { {} }

      it "always returns empty hash" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
