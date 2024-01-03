require "minitest"

RSpec.describe Datadog::CI::Contrib::Minitest::Patcher do
  describe ".patch" do
    subject!(:patch) { described_class.patch }

    context "Minitest::Test is patched" do
      let(:test) { Minitest::Test }
      it "has a custom bases" do
        expect(test.ancestors).to include(Datadog::CI::Contrib::Minitest::Hooks)
      end
    end

    context "Minitest::Runnable is patched" do
      let(:runnable) { Minitest::Runnable }
      it "has a custom bases" do
        expect(runnable.ancestors).to include(Datadog::CI::Contrib::Minitest::Runnable)
      end
    end

    context "Minitest includes plugin" do
      let(:minitest) { Minitest }
      it "has a custom bases" do
        expect(minitest.ancestors).to include(Datadog::CI::Contrib::Minitest::Plugin)
      end

      it "has datadog_ci extension" do
        expect(minitest.extensions).to include("datadog_ci")
      end
    end
  end
end
