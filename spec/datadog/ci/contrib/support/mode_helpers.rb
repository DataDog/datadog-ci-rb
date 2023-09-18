RSpec.shared_context "CI mode activated" do
  let(:integration_name) { :override_me }
  let(:integration_options) { {} }

  before do
    Datadog.configure do |c|
      c.ci.enabled = true
      c.ci.instrument integration_name, integration_options
    end
  end

  after do
    ::Datadog::Tracing.shutdown!
  end
end
