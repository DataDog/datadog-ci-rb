require_relative "../../../../../lib/datadog/ci/transport/api/builder"

RSpec.describe Datadog::CI::Transport::Api::Builder do
  let(:settings) { Datadog::CI::Configuration::RuntimeSettings.new(environment: {}) }

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
    let(:endpoints) { [] }
    let(:agent_settings) { described_class.resolve_agent_settings(settings) }
    let(:transport) { instance_double(Datadog::CI::Transport::HTTP) }
    let(:response) { double(:response, error: error, ok?: true, payload: {endpoints: endpoints}.to_json) }
    let(:error) { nil }

    before do
      settings.agent.host = "localhost"
      settings.agent.port = 5555
      settings.agent.timeout_seconds = 42
      allow(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "localhost", port: 5555, ssl: false, timeout: 42, uds_path: nil
      ).and_return(transport)
      allow(transport).to receive(:request).with(path: "/info", payload: "", headers: {}, verb: "get").and_return(response)
    end

    context "agent does not support any evp proxy version" do
      it { is_expected.to eq([nil, true]) }
    end

    context "when the Agent response does not contain endpoints" do
      let(:endpoints) { nil }

      it { is_expected.to eq([nil, true]) }
    end

    context "when the Agent response endpoints are not an array" do
      let(:endpoints) { "/evp_proxy/v4/" }

      it { is_expected.to eq([nil, true]) }
    end

    context "agent supports evp proxy v2" do
      let(:endpoints) { ["/evp_proxy/v2/"] }

      it "creates and configures http client and EvpProxy" do
        expect(Datadog::CI::Transport::Api::EvpProxy).to(
          receive(:new).with(agent_settings: agent_settings, path_prefix: "/evp_proxy/v2/").and_return(api)
        )

        expect(subject).to eq([api, true])
      end
    end

    context "agent supports evp proxy v4" do
      let(:endpoints) { ["/evp_proxy/v4/", "/evp_proxy/v2/"] }

      it "creates and configures http client and EvpProxy" do
        expect(Datadog::CI::Transport::Api::EvpProxy).to(
          receive(:new).with(agent_settings: agent_settings, path_prefix: "/evp_proxy/v4/").and_return(api)
        )

        expect(subject).to eq([api, true])
      end
    end

    context "when the agent request has an internal transport error" do
      let(:error) { Errno::ECONNREFUSED.new }

      it { is_expected.to eq([nil, false]) }
    end

    it "requests Agent information once" do
      subject

      expect(transport).to have_received(:request).once
    end
  end

  describe ".resolve_agent_settings" do
    subject(:resolved) { described_class.resolve_agent_settings(settings) }

    let(:environment) { {} }
    let(:settings) { Datadog::CI::Configuration::RuntimeSettings.new(environment: environment) }

    before { allow(File).to receive(:socket?).with("/var/run/datadog/apm.socket").and_return(false) }

    it "uses the default HTTP Agent address" do
      expect(resolved).to have_attributes(hostname: "127.0.0.1", port: 8126, ssl: false, timeout_seconds: 30, uds_path: nil)
    end

    context "with environment host and port" do
      let(:environment) { {"DD_AGENT_HOST" => "env.example.test", "DD_TRACE_AGENT_PORT" => "9126"} }

      it "keeps environment values when legacy configuration has no values" do
        settings.import_legacy!(Datadog::Core::Configuration::Settings.new)
        expect(resolved).to have_attributes(hostname: "env.example.test", port: 9126)
      end

      it "uses explicit legacy values before the environment" do
        legacy = Datadog::Core::Configuration::Settings.new
        legacy.agent.host = "legacy.example.test"
        legacy.agent.port = 8127
        settings.import_legacy!(legacy)
        expect(resolved).to have_attributes(hostname: "legacy.example.test", port: 8127)
      end

      it "returns to environment values when legacy values are cleared" do
        legacy = Datadog::Core::Configuration::Settings.new
        legacy.agent.host = "legacy.example.test"
        settings.import_legacy!(legacy)
        legacy.agent.host = nil
        settings.import_legacy!(legacy)
        expect(resolved.hostname).to eq("env.example.test")
      end
    end

    context "with an HTTPS URL and environment host and port" do
      let(:environment) do
        {"DD_AGENT_HOST" => "env.example.test", "DD_TRACE_AGENT_PORT" => "9126",
         "DD_TRACE_AGENT_URL" => "https://url.example.test:443"}
      end

      it "uses the URL before individual environment values" do
        expect(resolved).to have_attributes(hostname: "url.example.test", port: 443, ssl: true)
      end

      it "uses native explicit host, port, and false SSL before the URL" do
        settings.agent.host = "native.example.test"
        settings.agent.port = "8128"
        settings.agent.use_ssl = false
        settings.import_legacy!(Datadog::Core::Configuration::Settings.new)
        expect(resolved).to have_attributes(hostname: "native.example.test", port: 8128, ssl: false)
      end

      it "uses legacy explicit host, port, and false SSL before the URL" do
        legacy = Datadog::Core::Configuration::Settings.new
        legacy.agent.host = "legacy.example.test"
        legacy.agent.port = 8127
        legacy.agent.use_ssl = false
        settings.import_legacy!(legacy)
        expect(resolved).to have_attributes(hostname: "legacy.example.test", port: 8127, ssl: false)
      end
    end

    context "with an IPv6 URL" do
      let(:environment) { {"DD_TRACE_AGENT_URL" => "http://[::1]:8127"} }

      it "removes URL brackets from the connection hostname" do
        expect(resolved).to have_attributes(hostname: "::1", port: 8127)
      end
    end

    ["unix:///tmp/apm.socket", "unix:/tmp/apm.socket"].each do |url|
      context "with #{url}" do
        let(:environment) { {"DD_TRACE_AGENT_URL" => url} }

        it "uses the configured Unix socket without TLS" do
          settings.agent.use_ssl = true
          expect(resolved).to have_attributes(uds_path: "/tmp/apm.socket", ssl: false)
        end
      end
    end

    context "with the default Unix socket present" do
      before { allow(File).to receive(:socket?).with("/var/run/datadog/apm.socket").and_return(true) }

      it "uses the socket when no address is configured" do
        expect(resolved.uds_path).to eq("/var/run/datadog/apm.socket")
      end

      it "uses an explicit HTTP address before the default socket" do
        settings.agent.host = "localhost"
        expect(resolved.uds_path).to be_nil
      end
    end

    context "with an invalid Agent URL and port" do
      let(:environment) { {"DD_TRACE_AGENT_URL" => "ftp://example.test", "DD_TRACE_AGENT_PORT" => "invalid"} }

      it "falls back to the default HTTP address" do
        expect(resolved).to have_attributes(hostname: "127.0.0.1", port: 8126)
      end
    end

    context "with an invalid URL string" do
      let(:environment) { {"DD_TRACE_AGENT_URL" => "not an address", "DD_AGENT_HOST" => "fallback.example.test"} }

      it "falls back to the environment host" do
        expect(resolved.hostname).to eq("fallback.example.test")
      end
    end

    context "with an environment timeout" do
      let(:environment) { {"DD_TRACE_AGENT_TIMEOUT_SECONDS" => "9"} }

      it "keeps the timeout after legacy import" do
        settings.import_legacy!(Datadog::Core::Configuration::Settings.new)
        expect(resolved.timeout_seconds).to eq(9)
      end

      it "uses an explicit timeout before the environment" do
        settings.agent.timeout_seconds = 4
        expect(resolved.timeout_seconds).to eq(4)
      end
    end

    context "with a fractional environment timeout" do
      let(:environment) { {"DD_TRACE_AGENT_TIMEOUT_SECONDS" => "0.5"} }

      it "preserves fractions after legacy import" do
        settings.import_legacy!(Datadog::Core::Configuration::Settings.new)
        expect(resolved.timeout_seconds).to eq(0.5)
      end

      it "preserves a fractional timeout from native configuration" do
        settings.agent.timeout_seconds = 0.25
        expect(resolved.timeout_seconds).to eq(0.25)
      end

      it "preserves a fractional timeout from legacy configuration" do
        legacy = Datadog::Core::Configuration::Settings.new
        legacy.agent.timeout_seconds = 0.75
        settings.import_legacy!(legacy)
        expect(resolved.timeout_seconds).to eq(0.75)
      end
    end

    ["NaN", "Infinity", "-1"].each do |timeout|
      context "with invalid timeout #{timeout}" do
        let(:environment) { {"DD_TRACE_AGENT_TIMEOUT_SECONDS" => timeout} }

        it "uses the default timeout" do
          expect(resolved.timeout_seconds).to eq(30)
        end
      end
    end
  end
end
