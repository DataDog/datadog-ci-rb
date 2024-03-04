# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/itr/runner"

RSpec.describe Datadog::CI::ITR::Runner do
  let(:itr_enabled) { true }

  subject(:runner) { described_class.new(enabled: itr_enabled) }

  describe "#disable" do
    it "disables the runner" do
      expect { runner.disable }.to change { runner.enabled? }.from(true).to(false)
    end
  end
end
