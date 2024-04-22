require_relative "../../../../lib/datadog/ci/utils/test_run"

RSpec.describe ::Datadog::CI::Utils::TestRun do
  describe ".command" do
    subject { described_class.command }

    it { is_expected.to eq("#{$0} #{ARGV.join(" ")}") }
  end

  describe ".skippable_test_id" do
    subject { described_class.skippable_test_id(test_name, suite, parameters) }

    let(:test_name) { "test_name" }
    let(:suite) { "suite" }
    let(:parameters) { "parameters" }

    it { is_expected.to eq("suite.test_name.parameters") }
  end

  describe ".test_parameters" do
    subject { described_class.test_parameters(arguments: arguments, metadata: metadata) }

    let(:arguments) { {} }
    let(:metadata) { {} }

    it "returns a JSON string" do
      is_expected.to eq(
        JSON.generate(
          {
            arguments: arguments,
            metadata: metadata
          }
        )
      )
    end
  end
end
