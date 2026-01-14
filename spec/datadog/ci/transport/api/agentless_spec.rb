require_relative "../../../../../lib/datadog/ci/transport/api/agentless"

RSpec.describe Datadog::CI::Transport::Api::Agentless do
  subject do
    described_class.new(
      api_key: api_key,
      citestcycle_url: citestcycle_url,
      citestcov_url: citestcov_url,
      api_url: api_url,
      logs_intake_url: logs_intake_url,
      cicovreprt_url: cicovreprt_url
    )
  end

  let(:api_key) { "api_key" }

  context "malformed urls" do
    let(:citestcycle_url) { "" }
    let(:api_url) { "api.datadoghq.com" }
    let(:citestcov_url) { "citestcov.datadoghq.com" }
    let(:logs_intake_url) { "logs.datadoghq.com" }
    let(:cicovreprt_url) { "ci-intake.datadoghq.com" }

    it { expect { subject }.to raise_error(/Invalid agentless mode URL:/) }
  end

  context "http urls" do
    let(:citestcycle_url) { "http://localhost:5555" }
    let(:citestcycle_http) { double(:http) }

    let(:api_url) { "http://localhost:5555" }
    let(:api_http) { double(:http) }

    let(:citestcov_url) { "http://localhost:5555" }
    let(:citestcov_http) { double(:http) }

    let(:logs_intake_url) { "http://localhost:5555" }
    let(:logs_intake_http) { double(:http) }

    let(:cicovreprt_url) { "http://localhost:5555" }
    let(:cicovreprt_http) { double(:http) }

    before do
      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "localhost",
        port: 5555,
        ssl: false,
        compress: true
      ).and_return(citestcycle_http)

      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "localhost",
        port: 5555,
        ssl: false,
        compress: false
      ).and_return(api_http)

      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "localhost",
        port: 5555,
        ssl: false,
        compress: true
      ).and_return(citestcov_http)

      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "localhost",
        port: 5555,
        ssl: false,
        compress: true
      ).and_return(logs_intake_http)

      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "localhost",
        port: 5555,
        ssl: false,
        compress: false
      ).and_return(cicovreprt_http)
    end

    describe "#citestcycle_request" do
      let(:expected_headers) do
        {
          "DD-API-KEY" => "api_key",
          "Content-Type" => "application/msgpack"
        }
      end

      it "produces correct headers and forwards request to HTTP layer" do
        expect(citestcycle_http).to receive(:request).with(
          path: "path",
          payload: "payload",
          verb: "post",
          headers: expected_headers,
          accept_compressed_response: false
        )

        subject.citestcycle_request(path: "path", payload: "payload")
      end
    end

    describe "#logs_intake_request" do
      let(:expected_headers) do
        {
          "DD-API-KEY" => "api_key",
          "Content-Type" => "application/json"
        }
      end

      it "produces correct headers and forwards request to HTTP layer" do
        expect(logs_intake_http).to receive(:request).with(
          path: "path",
          payload: "payload",
          verb: "post",
          headers: expected_headers,
          accept_compressed_response: false
        )

        subject.logs_intake_request(path: "path", payload: "payload")
      end

      it "allows to override headers" do
        expect(logs_intake_http).to receive(:request).with(
          path: "path",
          payload: "payload",
          verb: "post",
          headers: expected_headers.merge({"Content-Type" => "application/msgpack"}),
          accept_compressed_response: false
        )

        subject.logs_intake_request(path: "path", payload: "payload", headers: {"Content-Type" => "application/msgpack"})
      end
    end
  end

  context "valid urls" do
    let(:citestcycle_url) { "https://citestcycle-intake.datadoghq.com:443" }
    let(:citestcycle_http) { double(:http) }

    let(:api_url) { "https://api.datadoghq.com:443" }
    let(:api_http) { double(:http) }

    let(:citestcov_url) { "https://citestcov-intake.datadoghq.com:443" }
    let(:citestcov_http) { double(:http) }

    let(:logs_intake_url) { "https://http-intake.logs.datadoghq.com:443" }
    let(:logs_intake_http) { double(:http) }

    let(:cicovreprt_url) { "https://ci-intake.datadoghq.com:443" }
    let(:cicovreprt_http) { double(:http) }

    before do
      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "citestcycle-intake.datadoghq.com",
        port: 443,
        ssl: true,
        compress: true
      ).and_return(citestcycle_http)

      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "api.datadoghq.com",
        port: 443,
        ssl: true,
        compress: false
      ).and_return(api_http)

      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "citestcov-intake.datadoghq.com",
        port: 443,
        ssl: true,
        compress: true
      ).and_return(citestcov_http)

      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "http-intake.logs.datadoghq.com",
        port: 443,
        ssl: true,
        compress: true
      ).and_return(logs_intake_http)

      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: "ci-intake.datadoghq.com",
        port: 443,
        ssl: true,
        compress: false
      ).and_return(cicovreprt_http)
    end

    describe "#citestcycle_request" do
      let(:expected_headers) do
        {
          "DD-API-KEY" => "api_key",
          "Content-Type" => "application/msgpack"
        }
      end

      it "produces correct headers and forwards request to HTTP layer" do
        expect(citestcycle_http).to receive(:request).with(
          path: "path",
          payload: "payload",
          verb: "post",
          headers: expected_headers,
          accept_compressed_response: false
        )

        subject.citestcycle_request(path: "path", payload: "payload")
      end

      it "alows to override headers" do
        expect(citestcycle_http).to receive(:request).with(
          path: "path",
          payload: "payload",
          verb: "post",
          headers: expected_headers.merge({"Content-Type" => "application/json"}),
          accept_compressed_response: false
        )

        subject.citestcycle_request(path: "path", payload: "payload", headers: {"Content-Type" => "application/json"})
      end
    end

    describe "#api_request" do
      let(:expected_headers) do
        {
          "DD-API-KEY" => "api_key",
          "Content-Type" => "application/msgpack"
        }
      end

      it "produces correct headers and forwards request to HTTP layer" do
        expect(api_http).to receive(:request).with(
          path: "path",
          payload: "payload",
          verb: "post",
          headers: {
            "DD-API-KEY" => "api_key",
            "Content-Type" => "application/json"
          },
          accept_compressed_response: true
        )

        subject.api_request(path: "path", payload: "payload")
      end
    end

    describe "#citestcov_request" do
      before do
        expect(SecureRandom).to receive(:uuid).and_return("42")
      end

      let(:expected_headers) do
        {
          "DD-API-KEY" => "api_key",
          "Content-Type" => "multipart/form-data; boundary=42"
        }
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
        allow(citestcov_http).to receive(:request)

        subject.citestcov_request(path: "path", payload: "payload")

        expect(citestcov_http).to have_received(:request) do |args|
          expect(args[:path]).to eq("path")
          expect(args[:verb]).to eq("post")
          expect(args[:headers]).to eq(expected_headers)
          expect(args[:payload]).to eq(expected_payload)
          expect(args[:accept_compressed_response]).to eq(false)
        end
      end
    end

    describe "#cicovreprt_request" do
      before do
        expect(SecureRandom).to receive(:uuid).and_return("abc123")
      end

      let(:expected_headers) do
        {
          "DD-API-KEY" => "api_key",
          "Content-Type" => "multipart/form-data; boundary=abc123"
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
        allow(cicovreprt_http).to receive(:request)

        subject.cicovreprt_request(
          path: "path",
          event_payload: '{"type":"coverage_report"}',
          coverage_report_compressed: "compressed_coverage"
        )

        expect(cicovreprt_http).to have_received(:request) do |args|
          expect(args[:path]).to eq("path")
          expect(args[:verb]).to eq("post")
          expect(args[:headers]).to eq(expected_headers)
          expect(args[:payload]).to eq(expected_payload)
          expect(args[:accept_compressed_response]).to eq(false)
        end
      end
    end
  end
end
