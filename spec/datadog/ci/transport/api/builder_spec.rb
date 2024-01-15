require_relative "../../../../../lib/datadog/ci/transport/api/builder"

RSpec.describe Datadog::CI::Transport::Api::Builder do
  let(:settings) do
    # When 'datadog/ci' is required, it automatically extends Settings.
    if Datadog::Core::Configuration::Settings <= Datadog::CI::Configuration::Settings
      Datadog::Core::Configuration::Settings.new
    else
      Datadog::Core::Configuration::Settings.new.tap do |settings|
        settings.extend(Datadog::CI::Configuration::Settings)
      end
    end
  end

  describe ".build_ci_test_cycle_api" do
    subject { described_class.build_ci_test_cycle_api(settings) }

    let(:api) { double(:api) }
    let(:http) { double(:http) }
    let(:agentless_url) { nil }
    let(:dd_site) { nil }
    let(:api_key) { "api_key" }

    before do
      # Stub CI mode behavior
      allow(settings.ci)
        .to receive(:agentless_url)
        .and_return(agentless_url)

      allow(settings)
        .to receive(:site)
        .and_return(dd_site)

      allow(settings)
        .to receive(:api_key)
        .and_return(api_key)
    end

    it "creates and configures http client and CiTestCycle" do
      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "citestcycle-intake.datadoghq.com",
        port: 443,
        ssl: true,
        compress: true
      ).and_return(http)

      expect(Datadog::CI::Transport::Api::CiTestCycle).to receive(:new).with(
        api_key: "api_key", http: http
      ).and_return(api)

      expect(subject).to eq(api)
    end

    context "when agentless_url is provided" do
      let(:agentless_url) { "http://localhost:5555" }

      it "configures transport to use intake URL from settings" do
        expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
          host: "localhost",
          port: 5555,
          ssl: false,
          compress: true
        ).and_return(http)

        expect(Datadog::CI::Transport::Api::CiTestCycle).to receive(:new).with(
          api_key: "api_key", http: http
        ).and_return(api)

        expect(subject).to eq(api)
      end
    end

    context "when dd_site is provided" do
      let(:dd_site) { "datadoghq.eu" }

      it "construct intake url using provided host" do
        expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
          host: "citestcycle-intake.datadoghq.eu",
          port: 443,
          ssl: true,
          compress: true
        ).and_return(http)

        expect(Datadog::CI::Transport::Api::CiTestCycle).to receive(:new).with(
          api_key: "api_key", http: http
        ).and_return(api)

        expect(subject).to eq(api)
      end
    end
  end

  describe ".build_evp_proxy_api" do
    subject { described_class.build_evp_proxy_api(agent_settings) }

    let(:api) { double(:api) }
    let(:http) { double(:http) }

    let(:agent_settings) do
      Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
        adapter: nil,
        ssl: false,
        hostname: "localhost",
        port: 5555,
        uds_path: nil,
        timeout_seconds: 42,
        deprecated_for_removal_transport_configuration_proc: nil
      )
    end

    it "creates and configures http client and EvpProxy" do
      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "localhost",
        port: 5555,
        ssl: false,
        timeout: 42,
        compress: false
      ).and_return(http)

      expect(Datadog::CI::Transport::Api::EvpProxy).to receive(:new).with(http: http).and_return(api)

      expect(subject).to eq(api)
    end
  end
end
