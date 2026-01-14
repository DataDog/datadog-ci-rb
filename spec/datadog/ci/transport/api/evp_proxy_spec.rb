require_relative "../../../../../lib/datadog/ci/transport/api/evp_proxy"

RSpec.describe Datadog::CI::Transport::Api::EvpProxy do
  subject do
    described_class.new(agent_settings: agent_settings, path_prefix: path_prefix)
  end

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
  let(:intake_http) { double(:http) }
  let(:api_http) { double(:http) }

  let(:container_id) { nil }

  let(:citestcycle_headers) do
    {
      "Content-Type" => "application/msgpack",
      "X-Datadog-EVP-Subdomain" => "citestcycle-intake"
    }
  end

  let(:api_headers) do
    {
      "Content-Type" => "application/json",
      "X-Datadog-EVP-Subdomain" => "api"
    }
  end

  let(:citestcov_headers) do
    {
      "Content-Type" => "multipart/form-data; boundary=42",
      "X-Datadog-EVP-Subdomain" => "citestcov-intake"
    }
  end

  context "with evp proxy v2" do
    let(:path_prefix) { Datadog::CI::Ext::Transport::EVP_PROXY_V2_PATH_PREFIX }

    before do
      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: agent_settings.hostname,
        port: agent_settings.port,
        ssl: agent_settings.ssl,
        timeout: agent_settings.timeout_seconds,
        compress: false
      ).and_return(intake_http, api_http)
    end

    describe "#citestcycle_request" do
      before do
        expect(Datadog::Core::Environment::Container).to receive(:container_id).and_return(container_id)
      end

      context "with path starting from / character" do
        it "produces correct headers and forwards request to HTTP layer prepending path with evp_proxy" do
          expect(intake_http).to receive(:request).with(
            path: "/evp_proxy/v2/path",
            payload: "payload",
            verb: "post",
            headers: citestcycle_headers
          )

          subject.citestcycle_request(path: "/path", payload: "payload")
        end
      end

      context "with path without / in the beginning" do
        it "constructs evp proxy path correctly" do
          expect(intake_http).to receive(:request).with(
            path: "/evp_proxy/v2/path",
            payload: "payload",
            verb: "post",
            headers: citestcycle_headers
          )

          subject.citestcycle_request(path: "path", payload: "payload")
        end
      end

      context "with container id" do
        let(:container_id) { "container-id" }

        it "adds an additional Datadog-Container-ID header" do
          expect(intake_http).to receive(:request).with(
            path: "/evp_proxy/v2/path",
            payload: "payload",
            verb: "post",
            headers: citestcycle_headers.merge("Datadog-Container-ID" => "container-id")
          )

          subject.citestcycle_request(path: "/path", payload: "payload")
        end
      end

      context "overriding content-type" do
        it "uses content type header from the request parameter" do
          expect(intake_http).to receive(:request).with(
            path: "/evp_proxy/v2/path",
            payload: "payload",
            verb: "post",
            headers: citestcycle_headers.merge({"Content-Type" => "application/json"})
          )

          subject.citestcycle_request(path: "/path", payload: "payload", headers: {"Content-Type" => "application/json"})
        end
      end
    end

    describe "#api_request" do
      before do
        expect(Datadog::Core::Environment::Container).to receive(:container_id).and_return(container_id)
      end

      context "with path starting from / character" do
        it "produces correct headers and forwards request to HTTP layer prepending path with evp_proxy" do
          expect(api_http).to receive(:request).with(
            path: "/evp_proxy/v2/path",
            payload: "payload",
            verb: "post",
            headers: api_headers
          )

          subject.api_request(path: "/path", payload: "payload")
        end
      end

      context "with path without / in the beginning" do
        it "constructs evp proxy path correctly" do
          expect(api_http).to receive(:request).with(
            path: "/evp_proxy/v2/path",
            payload: "payload",
            verb: "post",
            headers: api_headers
          )

          subject.api_request(path: "path", payload: "payload")
        end
      end

      context "with container id" do
        let(:container_id) { "container-id" }

        it "adds an additional Datadog-Container-ID header" do
          expect(api_http).to receive(:request).with(
            path: "/evp_proxy/v2/path",
            payload: "payload",
            verb: "post",
            headers: api_headers.merge("Datadog-Container-ID" => "container-id")
          )

          subject.api_request(path: "/path", payload: "payload")
        end
      end
    end

    describe "#citestcov_request" do
      before do
        expect(Datadog::Core::Environment::Container).to receive(:container_id).and_return(container_id)
        expect(SecureRandom).to receive(:uuid).and_return("42")
      end

      let(:expected_payload) do
        [
          "--42",
          'Content-Disposition: form-data; name="event"; filename="event.json"',
          "Content-Type: application/json",
          "",
          '{"dummy":true}',
          "--42",
          'Content-Disposition: form-data; name="coverage1"; filename="coverage1.msgpack"',
          "Content-Type: application/msgpack",
          "",
          "payload",
          "--42--"
        ].join("\r\n")
      end

      it "produces correct headers, constructs multipart payload, and forwards request to HTTP layer" do
        expect(intake_http).to receive(:request).with(
          path: "/evp_proxy/v2/path",
          payload: expected_payload,
          verb: "post",
          headers: citestcov_headers
        )

        subject.citestcov_request(path: "/path", payload: "payload")
      end
    end

    describe "#logs_intake_request" do
      it "raises NotImplementedError" do
        expect do
          subject.logs_intake_request(path: "/path", payload: "payload")
        end.to raise_error(NotImplementedError, "Logs intake is not supported in EVP proxy mode")
      end
    end

    describe "#cicovreprt_request" do
      before do
        expect(Datadog::Core::Environment::Container).to receive(:container_id).and_return(container_id)
        expect(SecureRandom).to receive(:uuid).and_return("abc123")
      end

      let(:cicovreprt_headers) do
        {
          "Content-Type" => "multipart/form-data; boundary=abc123",
          "X-Datadog-EVP-Subdomain" => "ci-intake"
        }
      end

      let(:expected_payload) do
        [
          "--abc123",
          'Content-Disposition: form-data; name="event"; filename="event.json"',
          "Content-Type: application/json",
          "",
          '{"type":"coverage_report"}',
          "--abc123",
          'Content-Disposition: form-data; name="coverage"; filename="coverage.gz"',
          "Content-Type: application/octet-stream",
          "",
          "compressed_coverage",
          "--abc123--"
        ].join("\r\n")
      end

      it "produces correct headers, constructs multipart payload, and forwards request to HTTP layer" do
        expect(intake_http).to receive(:request).with(
          path: "/evp_proxy/v2/path",
          payload: expected_payload,
          verb: "post",
          headers: cicovreprt_headers
        )

        subject.cicovreprt_request(
          path: "/path",
          event_payload: '{"type":"coverage_report"}',
          coverage_report_compressed: "compressed_coverage"
        )
      end

      context "with container id" do
        let(:container_id) { "container-id" }

        it "adds an additional Datadog-Container-ID header" do
          expect(intake_http).to receive(:request).with(
            path: "/evp_proxy/v2/path",
            payload: expected_payload,
            verb: "post",
            headers: cicovreprt_headers.merge("Datadog-Container-ID" => "container-id")
          )

          subject.cicovreprt_request(
            path: "/path",
            event_payload: '{"type":"coverage_report"}',
            coverage_report_compressed: "compressed_coverage"
          )
        end
      end
    end
  end

  context "with evp proxy v4" do
    let(:path_prefix) { Datadog::CI::Ext::Transport::EVP_PROXY_V4_PATH_PREFIX }

    before do
      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: agent_settings.hostname,
        port: agent_settings.port,
        ssl: agent_settings.ssl,
        timeout: agent_settings.timeout_seconds,
        compress: true
      ).and_return(intake_http)

      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: agent_settings.hostname,
        port: agent_settings.port,
        ssl: agent_settings.ssl,
        timeout: agent_settings.timeout_seconds,
        compress: false
      ).and_return(api_http)
    end

    describe "#citestcycle_request" do
      it "constructs evp proxy path using v4 prefix" do
        expect(intake_http).to receive(:request).with(
          path: "/evp_proxy/v4/path",
          payload: "payload",
          verb: "post",
          headers: citestcycle_headers
        )

        subject.citestcycle_request(path: "path", payload: "payload")
      end
    end

    describe "#api_request" do
      it "constructs evp proxy path using v4 prefix" do
        expect(api_http).to receive(:request).with(
          path: "/evp_proxy/v4/path",
          payload: "payload",
          verb: "post",
          headers: api_headers
        )

        subject.api_request(path: "path", payload: "payload")
      end
    end
  end
end
