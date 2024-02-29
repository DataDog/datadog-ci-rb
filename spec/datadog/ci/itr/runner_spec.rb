# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/itr/runner"

RSpec.describe Datadog::CI::ITR::Runner do
  let(:itr_enabled) { true }
  subject(:runner) { described_class.new(enabled: itr_enabled) }

  describe "#configure" do
    context "itr enabled" do
      before do
        expect(Datadog.logger).to receive(:debug).with("Sending ITR settings request...")
      end

      it { runner.configure }
    end

    context "itr disabled" do
      let(:itr_enabled) { false }

      before do
        expect(Datadog.logger).to_not receive(:debug).with("Sending ITR settings request...")
      end

      it { runner.configure }
    end
  end
end
