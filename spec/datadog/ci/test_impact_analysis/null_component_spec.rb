# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/test_impact_analysis/null_component"

RSpec.describe Datadog::CI::TestImpactAnalysis::NullComponent do
  subject(:test_impact_analysis) { described_class.new }

  describe "#test_skipping_mode?" do
    subject { test_impact_analysis.test_skipping_mode? }

    it { is_expected.to be(false) }
  end

  describe "#suite_skipping_mode?" do
    subject { test_impact_analysis.suite_skipping_mode? }

    it { is_expected.to be(false) }
  end
end
