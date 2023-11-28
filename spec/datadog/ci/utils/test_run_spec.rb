require_relative "../../../../lib/datadog/ci/utils/test_run"

RSpec.describe ::Datadog::CI::Utils::TestRun do
  describe ".command" do
    subject { described_class.command }

    it { is_expected.to eq("#{$0} #{ARGV.join(" ")}") }
  end
end
