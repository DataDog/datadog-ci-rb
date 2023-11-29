RSpec.shared_context "CI mode activated" do
  let(:test_command) { "command" }
  let(:integration_name) { :no_instrument }
  let(:integration_options) { {} }
  let(:experimental_test_suite_level_visibility_enabled) { true }
  let(:recorder) { Datadog.send(:components).ci_recorder }

  before do
    allow_any_instance_of(Datadog::Core::Remote::Negotiation).to(
      receive(:endpoint?).with("/evp_proxy/v2/").and_return(true)
    )

    allow(Datadog::CI::Utils::TestRun).to receive(:command).and_return(test_command)

    Datadog.configure do |c|
      c.ci.enabled = true
      c.ci.experimental_test_suite_level_visibility_enabled = experimental_test_suite_level_visibility_enabled
      unless integration_name == :no_instrument
        c.ci.instrument integration_name, integration_options
      end
    end
  end

  after do
    ::Datadog::Tracing.shutdown!
  end
end
