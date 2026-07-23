# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/contrib/simplecov/integration"

RSpec.describe Datadog::CI::Contrib::Simplecov::Integration do
  subject(:integration) { described_class.new }

  it "detects the loaded SimpleCov version" do
    expect(integration.version).to eq(Gem.loaded_specs.fetch("simplecov").version)
    expect(integration).to be_loaded
    expect(integration).to be_compatible
  end

  it "is late instrumented with the SimpleCov patcher" do
    expect(integration).to be_late_instrument
    expect(integration.patcher).to eq(Datadog::CI::Contrib::Simplecov::Patcher)
  end
end
