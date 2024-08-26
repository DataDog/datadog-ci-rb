RSpec.describe Datadog::CI::Contrib::Cucumber::Patcher do
  describe ".patch" do
    subject!(:patch) { described_class.patch }

    let(:runtime) { Cucumber::Runtime.new }

    before do
      described_class.patch
    end

    context "is patched" do
      let(:handlers) { runtime.configuration.event_bus.instance_variable_get(:@handlers) }

      it "has a custom formatter in formatters and adds event handlers" do
        expect(runtime.formatters).to include(runtime.datadog_formatter)

        [
          "Cucumber::Events::TestRunStarted",
          "Cucumber::Events::TestRunFinished",
          "Cucumber::Events::TestCaseStarted",
          "Cucumber::Events::TestCaseFinished",
          "Cucumber::Events::TestStepStarted",
          "Cucumber::Events::TestStepFinished"
        ].each do |event_name|
          expect(handlers).to include(event_name)
        end
      end
    end
  end
end
