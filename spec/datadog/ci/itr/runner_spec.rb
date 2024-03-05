# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/itr/runner"

RSpec.describe Datadog::CI::ITR::Runner do
  let(:itr_enabled) { true }

  subject(:runner) { described_class.new(enabled: itr_enabled) }

  describe "#configure" do
    before do
      runner.configure(remote_configuration)
    end

    context "when remote configuration call failed" do
      let(:remote_configuration) { {"itr_enabled" => false} }

      it "configures the runner" do
        expect(runner.enabled?).to be false
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be false
      end
    end

    context "when remote configuration call returned correct response" do
      let(:remote_configuration) { {"itr_enabled" => true, "code_coverage" => true, "tests_skipping" => false} }

      it "configures the runner" do
        expect(runner.enabled?).to be true
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be true
      end
    end

    context "when remote configuration call returned correct response with strings instead of bools" do
      let(:remote_configuration) { {"itr_enabled" => "true", "code_coverage" => "true", "tests_skipping" => "false"} }

      it "configures the runner" do
        expect(runner.enabled?).to be true
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be true
      end
    end

    context "when remote configuration call returns empty hash" do
      let(:remote_configuration) { {} }

      it "configures the runner" do
        expect(runner.enabled?).to be false
        expect(runner.skipping_tests?).to be false
        expect(runner.code_coverage?).to be false
      end
    end
  end
end
