shared_context "extract tags from environment with given provider and use a subject" do |git_fixture|
  subject(:extracted_tags) do
    ClimateControl.modify(environment_variables) do
      ::Datadog::CI::Ext::Environment::Extractor.new(env, provider_klass: described_class).tags
    end
  end

  let(:env) { {} }
  let(:environment_variables) { {} }
end
