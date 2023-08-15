require_relative "../support/spec_helper"

RSpec.describe Datadog::CI::Contrib::RSpec::Patcher do
  describe ".patch" do
    subject!(:patch) { described_class.patch }

    let(:example) { RSpec::Core::Example }

    context "is patched" do
      it "has a custom bases" do
        expect(example.ancestors).to include(Datadog::CI::Contrib::RSpec::Example::InstanceMethods)
      end
    end
  end
end
