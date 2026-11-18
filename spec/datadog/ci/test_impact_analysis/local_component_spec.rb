# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_impact_analysis/component"

RSpec.describe "Local TIA component wiring" do
  let(:store_class) { Datadog::CI::TestImpactAnalysis::Coverage::LocalStore }
  let(:store) { instance_double(store_class, collecting?: false) }
  let(:test_session) { instance_double(Datadog::CI::TestSession, distributed: false, git_repository_url: "https://github.com/team/project", get_tag: "rspec", set_internal_tag: nil) }
  let(:remote) { instance_double(Datadog::CI::Remote::LibrarySettings) }
  subject(:component) do
    Datadog::CI::TestImpactAnalysis::Component.build(
      api: nil, discard_traces: false, dd_env: nil, enabled: true,
      local_coverage_file: "tmp/coverage.json.gz"
    )
  end

  before { allow(store_class).to receive(:new).and_return(store) }

  it "uses structured identities without consulting backend selection" do
    expect(Datadog::CI::TestImpactAnalysis::Skippable).not_to receive(:new)
    component.configure(remote, test_session)
    expect(store).to receive(:skippable_identity?).with("suite", "test", '{"n":1}').and_return(true)
    expect(component.skippable?("legacy.id", suite: "suite", name: "test", parameters: '{"n":1}')).to be true
    expect(component.code_coverage?).to be false
  end

  it "disables selection after a failed reload" do
    component.configure(remote, test_session)
    expect(component.skipping_tests?).to be true
    allow(store_class).to receive(:new).and_raise(IOError, "unreadable map")
    expect(Datadog.logger).to receive(:warn).with(/Local TIA disabled/)
    expect { component.configure(remote, test_session) }.not_to raise_error
    expect(component.skippable?("test")).to be false
  end

  it "disables local selection for distributed sessions" do
    component.configure(remote, test_session)
    allow(test_session).to receive(:distributed).and_return(true)
    expect(Datadog.logger).to receive(:warn).with(/one process/)
    component.configure(remote, test_session)
    expect(component.skipping_tests?).to be false
    expect(component.code_coverage?).to be false
  end

  it "does not build backend transports or require an agent in local mode" do
    expect(Datadog::CI::Transport::Api::Builder).not_to receive(:build_agentless_api)
    expect(Datadog::CI::Transport::Api::Builder).not_to receive(:build_evp_proxy_api)
    expect(Datadog::CI::TestImpactAnalysis::Coverage::Transport).not_to receive(:new)
    Datadog.configure do |configuration|
      configuration.ci.enabled = true
      configuration.ci.tia_local_coverage_file = "tmp/coverage.json.gz"
    end
    expect(Datadog.configuration.ci.enabled).to be true
    expect(Datadog.configuration.telemetry.enabled).to be false
    expect(Datadog.send(:components).git_tree_upload_worker).to be_a(Datadog::CI::DummyWorker)
  end
end
