# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_optimization_cache/null_component"

RSpec.describe Datadog::CI::TestOptimizationCache::NullComponent do
  subject(:component) { described_class.new }

  it "is unavailable and does not load cache payloads" do
    expect(component.cache_available?).to be false
    expect(component.load_settings).to be_nil
    expect(component.load_known_tests).to be_nil
    expect(component.load_test_management).to be_nil
    expect(component.load_skippable_tests).to be_nil
  end

  it "can be shut down" do
    expect(component.shutdown!).to be_nil
  end
end
