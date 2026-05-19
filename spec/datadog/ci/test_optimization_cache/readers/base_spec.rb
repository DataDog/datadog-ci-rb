# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/test_optimization_cache/readers/base"

RSpec.describe Datadog::CI::TestOptimizationCache::Readers::Base do
  subject(:reader) { described_class.new }

  it "is available by default" do
    expect(reader.available?).to be true
  end

  it "requires concrete readers to implement endpoint loading" do
    expect { reader.load_settings }.to raise_error(NotImplementedError)
    expect { reader.load_known_tests }.to raise_error(NotImplementedError)
    expect { reader.load_test_management }.to raise_error(NotImplementedError)
    expect { reader.load_skippable_tests }.to raise_error(NotImplementedError)
  end
end
