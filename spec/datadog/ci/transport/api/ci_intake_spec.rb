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

  describe "#initialize" do
    context "with https URL" do
      it "creates SSL transport" do
        expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
          host: "citestcycle-intake.datad0ghq.com",
          port: 443,
          ssl: true,
          compress: true
        ).and_return(http)

        subject
      end
    end

    context "with http URL" do
      let(:url) { "http://localhost:5555" }

      it "creates http transport without SSL" do
        expect(Datadog::CI::Transport::HTTP).to receive(:new).with(
          host: "localhost",
          port: 5555,
          ssl: false,
          compress: true
        ).and_return(http)

        subject
      end
    end
  end

  describe "#request" do
    before do
      allow(Datadog::CI::Transport::HTTP).to receive(:new).and_return(http)
    end

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
