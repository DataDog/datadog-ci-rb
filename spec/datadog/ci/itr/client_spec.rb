require_relative "../../../../lib/datadog/ci/itr/client"
require_relative "../../../../lib/datadog/ci/ext/itr"

RSpec.describe Datadog::CI::ITR::Client do
  let(:api) { spy("api") }
  subject { described_class.new(api: api) }

  describe "#fetch_settings" do
    let(:service) { "service" }
    let(:path) { Datadog::CI::Ext::ITR::API_PATH_SETTINGS }
    let(:payload) do
      {
        data: {
          id: "change_me",
          type: Datadog::CI::Ext::ITR::API_TYPE_SETTINGS,
          attributes: {
            service: service
          }
        }
      }.to_json
    end

    it "requests the settings" do
      subject.fetch_settings(service: service)

      expect(api).to have_received(:request).with(
        path: path,
        payload: payload,
        headers: {"Content-Type" => "application/json"}
      )
    end
  end
end
