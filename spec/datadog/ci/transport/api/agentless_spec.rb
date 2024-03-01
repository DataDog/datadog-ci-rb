require_relative "../../../../../lib/datadog/ci/transport/api/agentless"

RSpec.describe Datadog::CI::Transport::Api::Agentless do
  subject do
    described_class.new(
      api_key: api_key,
      http: http
    )
  end

  let(:api_key) { "api_key" }
  let(:http) { double(:http) }

  describe "#request" do
    before do
      allow(Datadog::CI::Transport::HTTP).to receive(:new).and_return(http)
    end

    it "produces correct headers and forwards request to HTTP layer" do
      expect(http).to receive(:request).with(
        path: "path",
        payload: "payload",
        verb: "post",
        headers: {
          "DD-API-KEY" => "api_key",
          "Content-Type" => "application/msgpack"
        }
      )

      subject.request(path: "path", payload: "payload")
    end

    it "alows to override headers" do
      expect(http).to receive(:request).with(
        path: "path",
        payload: "payload",
        verb: "post",
        headers: {
          "DD-API-KEY" => "api_key",
          "Content-Type" => "application/json"
        }
      )

      subject.request(path: "path", payload: "payload", headers: {"Content-Type" => "application/json"})
    end
  end
end
