require "spec_helper"

require "datadog/ci/contrib/rspec/helpers"

RSpec.describe Datadog::CI::Contrib::RSpec::Helpers do
  describe ".parallel_tests?" do
    context "when both TEST_ENV_NUMBER and PARALLEL_TEST_GROUPS are set" do
      before do
        allow(ENV).to receive(:fetch).with("TEST_ENV_NUMBER", nil).and_return("1")
        allow(ENV).to receive(:fetch).with("PARALLEL_TEST_GROUPS", nil).and_return("4")
      end

      it "returns true" do
        expect(described_class.parallel_tests?).to be true
      end
    end

    context "when TEST_ENV_NUMBER is set but PARALLEL_TEST_GROUPS is not" do
      before do
        allow(ENV).to receive(:fetch).with("TEST_ENV_NUMBER", nil).and_return("1")
        allow(ENV).to receive(:fetch).with("PARALLEL_TEST_GROUPS", nil).and_return(nil)
      end

      it "returns false" do
        expect(described_class.parallel_tests?).to be false
      end
    end

    context "when PARALLEL_TEST_GROUPS is set but TEST_ENV_NUMBER is not" do
      before do
        allow(ENV).to receive(:fetch).with("TEST_ENV_NUMBER", nil).and_return(nil)
        allow(ENV).to receive(:fetch).with("PARALLEL_TEST_GROUPS", nil).and_return("4")
      end

      it "returns false" do
        expect(described_class.parallel_tests?).to be false
      end
    end

    context "when neither TEST_ENV_NUMBER nor PARALLEL_TEST_GROUPS are set" do
      before do
        allow(ENV).to receive(:fetch).with("TEST_ENV_NUMBER", nil).and_return(nil)
        allow(ENV).to receive(:fetch).with("PARALLEL_TEST_GROUPS", nil).and_return(nil)
      end

      it "returns false" do
        expect(described_class.parallel_tests?).to be false
      end
    end
  end
end
