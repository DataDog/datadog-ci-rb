require_relative "../../../../lib/datadog/ci/transport/api_client"

RSpec.describe Datadog::CI::Transport::ApiClient do
  let(:api) { spy("api") }
  subject { described_class.new(api: api) }

  describe "#fetch_library_settings" do
    let(:service) { "service" }
    let(:path) { Datadog::CI::Ext::Transport::DD_API_SETTINGS_PATH }
    let(:payload) do
      {
        data: {
          id: "change_me",
          type: Datadog::CI::Ext::Transport::DD_API_SETTINGS_TYPE,
          attributes: {
            service: service
          }
        }
      }.to_json
    end

    it "requests the settings" do
      subject.fetch_library_settings(service: service)

      expect(api).to have_received(:api_request).with(
        path: path,
        payload: payload
      )
    end
  end
end
