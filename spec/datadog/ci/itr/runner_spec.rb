# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/itr/client"
require_relative "../../../../lib/datadog/ci/itr/runner"

RSpec.describe Datadog::CI::ITR::Runner do
  let(:itr_enabled) { true }

  let(:api) { double("api") }
  let(:client) { double("client") }

  subject(:runner) { described_class.new(enabled: itr_enabled, api: api) }

  describe "#configure" do
    let(:service) { "service" }

    context "itr enabled" do
      before do
        expect(Datadog::CI::ITR::Client).to receive(:new).with(api: api).and_return(client)
      end

      it "fetches settings from backend" do
        expect(client).to receive(:fetch_settings).with(service: service)

        runner.configure(service: service)
      end
    end

    context "itr disabled" do
      let(:itr_enabled) { false }

      before do
        expect(Datadog::CI::ITR::Client).to_not receive(:new)
      end

      it "does nothing" do
        expect(runner.configure(service: service)).to be_nil
      end
    end
  end
end
