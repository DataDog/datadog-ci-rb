# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/test_optimization_cache/readers/missing"

RSpec.describe Datadog::CI::TestOptimizationCache::Readers::Missing do
  subject(:reader) { described_class.new }

  it "is unavailable and returns no cached endpoint data" do
    expect(reader.available?).to be false
    expect(reader.load_settings).to be_nil
    expect(reader.load_known_tests).to be_nil
    expect(reader.load_test_management).to be_nil
    expect(reader.load_skippable_tests).to be_nil
  end
end
