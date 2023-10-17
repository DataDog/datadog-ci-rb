require_relative "../../../../../lib/datadog/ci/transport/api/evp_proxy"

RSpec.describe Datadog::CI::Transport::Api::EVPProxy do
  subject do
    described_class.new(
      host: host,
      port: port,
      ssl: ssl,
      timeout: timeout
    )
  end

  let(:host) { "localhost" }
  let(:port) { 5555 }
  let(:ssl) { false }
  let(:timeout) { 42 }

  let(:http) { double(:http) }

  describe "#initialize" do
    it "creates HTTP transport" do
      expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
        host: host,
        port: port,
        ssl: ssl,
        timeout: timeout,
        compress: false
      ).and_return(http)

      subject
    end
  end

  describe "#request" do
    before do
      allow(Datadog::CI::Transport::HTTP).to receive(:new).and_return(http)
      expect(Datadog::Core::Environment::Container).to receive(:container_id).and_return(container_id)
    end

    context "without container id" do
      let(:container_id) { nil }

      it "produces correct headers and forwards request to HTTP layer" do
        expect(http).to receive(:request).with(
          path: "/evp_proxy/v2/path",
          payload: "payload",
          verb: "post",
          headers: {
            "Content-Type" => "application/msgpack",
            "X-Datadog-EVP-Subdomain" => "citestcycle-intake"
          }
        )

        subject.request(path: "/path", payload: "payload")
      end
    end

    context "with container id" do
      let(:container_id) { "container-id" }

      it "produces correct headers and forwards request to HTTP layer" do
        expect(http).to receive(:request).with(
          path: "/evp_proxy/v2/path",
          payload: "payload",
          verb: "post",
          headers: {
            "Content-Type" => "application/msgpack",
            "X-Datadog-EVP-Subdomain" => "citestcycle-intake",
            "Datadog-Container-ID" => "container-id"
          }
        )

        subject.request(path: "/path", payload: "payload")
      end
    end
  end
end
