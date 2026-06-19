# frozen_string_literal: true

require "json"

require_relative "../../../../lib/datadog/ci/utils/runtime_tags"

RSpec.describe Datadog::CI::Utils::RuntimeTags do
  describe ".parse" do
    subject(:runtime_tags) { described_class.parse(value) }

    context "when value is nil" do
      let(:value) { nil }

      it { is_expected.to eq({}) }
    end

    context "when value is blank" do
      let(:value) { "  " }

      it { is_expected.to eq({}) }
    end

    context "when value is valid JSON" do
      let(:value) do
        {
          "os.platform" => "linux",
          "os.architecture" => "arm64",
          "os.version" => " ubuntu-22.04 ",
          "runtime.name" => "ruby",
          "runtime.version" => "3.2.0",
          "custom.tag" => "ignored",
          "empty.tag" => ""
        }.to_json
      end

      it "returns supported runtime tags" do
        expect(runtime_tags).to eq(
          "os.platform" => "linux",
          "os.architecture" => "arm64",
          "os.version" => "ubuntu-22.04",
          "runtime.name" => "ruby",
          "runtime.version" => "3.2.0"
        )
      end
    end

    context "when values are not strings" do
      let(:value) { {"runtime.version" => 3.2}.to_json }

      it "stringifies values" do
        expect(runtime_tags).to eq("runtime.version" => "3.2")
      end
    end

    context "when value is invalid JSON" do
      let(:value) { "{invalid json}" }

      it "logs a warning and returns empty tags" do
        expect(Datadog.logger).to receive(:warn).with(/Invalid runtime tags configuration/)

        expect(runtime_tags).to eq({})
      end
    end

    context "when value is not a JSON object" do
      let(:value) { ["os.version"].to_json }

      it "logs a warning and returns empty tags" do
        expect(Datadog.logger).to receive(:warn).with("Invalid runtime tags configuration: expected JSON object")

        expect(runtime_tags).to eq({})
      end
    end
  end
end
