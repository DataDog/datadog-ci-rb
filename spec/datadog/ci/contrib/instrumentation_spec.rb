# frozen_string_literal: true

RSpec.describe Datadog::CI::Contrib::Instrumentation do
  describe ".remove_auto_instrumentation_from_rubyopt" do
    it "stops propagating auto instrumentation to fresh Ruby processes" do
      ClimateControl.modify("RUBYOPT" => "-rbundler/setup -rdatadog/ci/auto_instrument -W:no-deprecated") do
        described_class.remove_auto_instrumentation_from_rubyopt

        expect(ENV.fetch("RUBYOPT")).to eq("-rbundler/setup  -W:no-deprecated")
      end
    end

    it "removes auto instrumentation using the split require syntax" do
      ClimateControl.modify("RUBYOPT" => "-rbundler/setup -r datadog/ci/auto_instrument -W:no-deprecated") do
        described_class.remove_auto_instrumentation_from_rubyopt

        expect(ENV.fetch("RUBYOPT")).to eq("-rbundler/setup  -W:no-deprecated")
      end
    end

    it "removes RUBYOPT when it contains only auto instrumentation" do
      ClimateControl.modify("RUBYOPT" => "-rdatadog/ci/auto_instrument") do
        described_class.remove_auto_instrumentation_from_rubyopt

        expect(ENV).not_to have_key("RUBYOPT")
      end
    end

    it "preserves similar require paths" do
      ClimateControl.modify("RUBYOPT" => "-rdatadog/ci/auto_instrumentation") do
        described_class.remove_auto_instrumentation_from_rubyopt

        expect(ENV.fetch("RUBYOPT")).to eq("-rdatadog/ci/auto_instrumentation")
      end
    end
  end
end
