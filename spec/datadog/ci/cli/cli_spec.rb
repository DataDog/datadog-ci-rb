# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/cli/cli"

RSpec.describe Datadog::CI::CLI do
  describe ".exec" do
    context "when action is 'skipped-tests'" do
      it "uses SkippablePercentage::Calculator" do
        expect(Datadog::CI::TestOptimisation::SkippablePercentage::Calculator).to receive(:new).with({
          rspec_cli_options: [],
          spec_path: "spec",
          verbose: false
        }).and_return(
          double(call: nil, failed: false)
        )

        described_class.exec("skipped-tests")
      end
    end

    context "when action is 'skipped-tests-estimate'" do
      it "uses SkippablePercentage::Estimator" do
        expect(Datadog::CI::TestOptimisation::SkippablePercentage::Estimator).to receive(:new).with({
          spec_path: "spec",
          verbose: false
        }).and_return(
          double(call: nil, failed: false)
        )

        described_class.exec("skipped-tests-estimate")
      end
    end
  end
end
