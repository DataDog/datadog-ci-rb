RSpec.shared_context "CI mode activated" do
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.ci.enabled = true
    end
  end

  let(:components) { Datadog::Core::Configuration::Components.new(settings) }

  before do
    # TODO: this is a very hacky way that messes with Core's internals
    allow_any_instance_of(Datadog::Core::Configuration).to receive(:configuration).and_return(settings)

    allow(Datadog::Tracing)
      .to receive(:tracer)
      .and_return(components.tracer)
  end

  after { components.shutdown! }
end
