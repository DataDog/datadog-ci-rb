# Extract environment tags using described Provider.
# let(:environment_variables) can be used to set environment variables for the test.
shared_context "extract environment tags" do |git_fixture|
  subject(:extracted_tags) do
    ClimateControl.modify(environment_variables) do
      ::Datadog::CI::Ext::Environment::Extractor.new(env, provider_klass: described_class).tags
    end
  end

  let(:env) { {} }
  let(:environment_variables) { {} }
end
