require "minitest"

RSpec.describe Datadog::CI::Contrib::Minitest::Patcher do
  describe ".patch" do
    subject!(:patch) { described_class.patch }

    context "Minitest::Test is patched" do
      let(:test) { Minitest::Test }
      it "has a custom bases" do
        expect(test.ancestors).to include(Datadog::CI::Contrib::Minitest::Test)
      end
    end

    context "Minitest::Runnable is patched" do
      let(:runnable) { Minitest::Runnable }
      it "has a custom bases" do
        if ::Minitest::Runnable.respond_to?(:run_suite)
          expect(runnable.ancestors).to include(Datadog::CI::Contrib::Minitest::RunnableMinitest6)
        else
          expect(runnable.ancestors).to include(Datadog::CI::Contrib::Minitest::Runnable)
        end
      end
    end

    context "Minitest::CompositeReporter is patched" do
      let(:reporter) { Minitest::CompositeReporter }
      it "has a custom bases" do
        expect(reporter.ancestors).to include(Datadog::CI::Contrib::Minitest::Reporter)
      end
    end
  end
end
