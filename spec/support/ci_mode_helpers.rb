RSpec.shared_context "CI mode activated" do
  let(:test_command) { "command" }
  let(:integration_name) { :override_me }
  let(:integration_options) { {} }

  before do
    allow_any_instance_of(Datadog::Core::Remote::Negotiation).to(
      receive(:endpoint?).with("/evp_proxy/v2/").and_return(true)
    )

    allow(Datadog::CI::Utils::TestRun).to receive(:command).and_return(test_command)

    Datadog.configure do |c|
      c.ci.enabled = true
      c.ci.instrument integration_name, integration_options
    end
  end

  after do
    ::Datadog::Tracing.shutdown!
  end
end
