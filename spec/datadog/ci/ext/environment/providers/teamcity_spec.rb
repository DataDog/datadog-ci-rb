RSpec.describe ::Datadog::CI::Ext::Environment::Providers::Teamcity do
  describe ".tags" do
    include_context "extract tags from environment with given provider and use a subject"

    context "example fixture" do
      let(:env) do
        {
          "BUILD_URL" => "https://teamcity.com/repo",
          "TEAMCITY_BUILDCONF_NAME" => "Test 1",
          "TEAMCITY_VERSION" => "2022.10 (build 116751)"
        }
      end
      # Modify HOME so that '~' expansion matches CI home directory.
      let(:environment_variables) { super().merge("HOME" => env["HOME"]) }

      let(:expected_tags) do
        {
          "ci.job.name" => "Test 1",
          "ci.job.url" => "https://teamcity.com/repo",
          "ci.provider.name" => "teamcity"
        }
      end

      it "matches CI tags" do
        is_expected.to eq(expected_tags)
      end
    end
  end
end
