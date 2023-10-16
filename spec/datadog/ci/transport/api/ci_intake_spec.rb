require_relative "../../../../../lib/datadog/ci/transport/api/ci_intake"

RSpec.describe Datadog::CI::Transport::Api::CIIntake do
  subject do
    described_class.new(
      api_key: api_key,
      url: url
    )
  end

  let(:api_key) { "api_key" }
  let(:url) { "https://citestcycle-intake.datad0ghq.com:443" }

  let(:http) { double(:http) }

  before do
    expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
      host: "citestcycle-intake.datad0ghq.com",
      port: 443,
      ssl: true,
      compress: true
    ).and_return(http)
  end

  describe "#request" do
    it "produces correct headers and forwards request to HTTP layer" do
      expect(http).to receive(:request).with(
        path: "path",
        payload: "payload",
        method: "post",
        headers: {
          "DD-API-KEY" => "api_key",
          "Content-Type" => "application/msgpack"
        }
      )

      subject.request(path: "path", payload: "payload")
    end
  end
end
