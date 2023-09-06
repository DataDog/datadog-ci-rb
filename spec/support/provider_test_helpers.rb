shared_context "extract tags from environment with given provider and use a subject" do |git_fixture|
  let(:provider) do
    described_class.new(env)
  end

  subject(:extracted_tags) do
    ClimateControl.modify(environment_variables) do
      ::Datadog::CI::Ext::Environment::Extractor.new(env, provider: provider).tags
    end
  end

  let(:env) { {} }
  let(:environment_variables) { {} }
end
