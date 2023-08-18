require_relative "../support/spec_helper"

require "minitest"

RSpec.describe Datadog::CI::Contrib::Minitest::Patcher do
  describe ".patch" do
    subject!(:patch) { described_class.patch }

    let(:test) { Minitest::Test }

    context "is patched" do
      it "has a custom bases" do
        expect(test.ancestors).to include(Datadog::CI::Contrib::Minitest::Hooks)
      end
    end
  end
end
