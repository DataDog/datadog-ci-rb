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

  describe ".build_agentless_api" do
    subject { described_class.build_agentless_api(settings) }

    let(:api) { double(:api) }
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

    it "creates and configures http client and Agentless api" do
      expect(Datadog::CI::Transport::Api::Agentless).to receive(:new).with(
        api_key: "api_key",
        citestcycle_url: "https://citestcycle-intake.datadoghq.com:443",
        api_url: "https://api.datadoghq.com:443",
        citestcov_url: "https://citestcov-intake.datadoghq.com:443",
        logs_intake_url: "https://http-intake.logs.datadoghq.com:443",
        cicovreprt_url: "https://ci-intake.datadoghq.com:443"
      ).and_return(api)

      expect(subject).to eq(api)
    end

    context "when agentless_url is provided" do
      let(:agentless_url) { "http://localhost:5555" }

      it "configures transport to use intake URL from settings" do
        expect(Datadog::CI::Transport::Api::Agentless).to receive(:new).with(
          api_key: "api_key",
          citestcycle_url: "http://localhost:5555",
          api_url: "http://localhost:5555",
          citestcov_url: "http://localhost:5555",
          logs_intake_url: "http://localhost:5555",
          cicovreprt_url: "http://localhost:5555"
        ).and_return(api)

        expect(subject).to eq(api)
      end
    end

    context "when dd_site is provided" do
      let(:dd_site) { "datadoghq.eu" }

      it "construct intake url using provided host" do
        expect(Datadog::CI::Transport::Api::Agentless).to receive(:new).with(
          api_key: "api_key",
          citestcycle_url: "https://citestcycle-intake.datadoghq.eu:443",
          api_url: "https://api.datadoghq.eu:443",
          citestcov_url: "https://citestcov-intake.datadoghq.eu:443",
          logs_intake_url: "https://http-intake.logs.datadoghq.eu:443",
          cicovreprt_url: "https://ci-intake.datadoghq.eu:443"
        ).and_return(api)

        expect(subject).to eq(api)
      end
    end
  end

  describe ".build_evp_proxy_api" do
    subject { described_class.build_evp_proxy_api(settings) }

    let(:api) { double(:api) }

    let(:agent_settings) do
      Datadog::Core::Configuration::AgentSettings.new(
        adapter: :net_http,
        ssl: false,
        hostname: "localhost",
        port: 5555,
        uds_path: nil,
        timeout_seconds: 42
      )
    end

    before do
      allow(Datadog::Core::Configuration::AgentSettingsResolver).to receive(:call).and_return(agent_settings)
    end

    context "agent does not support any evp proxy version" do
      before do
        allow_any_instance_of(Datadog::Core::Remote::Negotiation).to(
          receive(:endpoint?).and_return(false)
        )
      end

      it { is_expected.to be_nil }
    end

    context "agent supports evp proxy v2" do
      before do
        allow_any_instance_of(Datadog::Core::Remote::Negotiation).to(
          receive(:endpoint?).with("/evp_proxy/v4/").and_return(false)
        )
        allow_any_instance_of(Datadog::Core::Remote::Negotiation).to(
          receive(:endpoint?).with("/evp_proxy/v2/").and_return(true)
        )
      end

      it "creates and configures http client and EvpProxy" do
        expect(Datadog::CI::Transport::Api::EvpProxy).to(
          receive(:new).with(agent_settings: agent_settings, path_prefix: "/evp_proxy/v2/").and_return(api)
        )

        expect(subject).to eq(api)
      end
    end

    context "agent supports evp proxy v4" do
      before do
        allow_any_instance_of(Datadog::Core::Remote::Negotiation).to(
          receive(:endpoint?).with("/evp_proxy/v4/").and_return(true)
        )
      end

      it "creates and configures http client and EvpProxy" do
        expect(Datadog::CI::Transport::Api::EvpProxy).to(
          receive(:new).with(agent_settings: agent_settings, path_prefix: "/evp_proxy/v4/").and_return(api)
        )

        expect(subject).to eq(api)
      end
    end
  end
end
