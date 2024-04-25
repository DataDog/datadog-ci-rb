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

  describe ".custom_configuration" do
    subject { described_class.custom_configuration(env_tags) }

    context "when env_tags is nil" do
      let(:env_tags) { nil }

      it { is_expected.to eq({}) }
    end

    context "when env_tags is not nil" do
      let(:env_tags) do
        {
          "test.configuration.tag1" => "value1",
          "test.configuration.tag2" => "value2",
          "tag3" => "value3",
          "test.configurations.tag4" => "value4",
          "test.configuration" => "value5"
        }
      end

      it { is_expected.to eq({"tag1" => "value1", "tag2" => "value2"}) }
    end
  end
end
