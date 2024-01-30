# CI mode shared context sets up the CI recorder and configures the CI mode for tracer like customers do.
# Example usage:
#
# include_context "CI mode activated" do
#   let(:integration_name) { :cucumber }
#   let(:integration_options) { {service_name: "jalapenos"} }
# end

RSpec.shared_context "CI mode activated" do
  let(:test_command) { "command" }
  let(:integration_name) { :no_instrument }
  let(:integration_options) { {} }

  let(:ci_enabled) { true }
  let(:force_test_level_visibility) { false }

  let(:recorder) { Datadog.send(:components).ci_recorder }

  before do
    allow_any_instance_of(Datadog::Core::Remote::Negotiation).to(
      receive(:endpoint?).with("/evp_proxy/v2/").and_return(true)
    )

    allow(Datadog::CI::Utils::TestRun).to receive(:command).and_return(test_command)

    Datadog.configure do |c|
      c.ci.enabled = ci_enabled
      c.ci.force_test_level_visibility = force_test_level_visibility
      unless integration_name == :no_instrument
        c.ci.instrument integration_name, integration_options
      end
    end
  end

  after do
    ::Datadog::Tracing.shutdown!
  end
end
