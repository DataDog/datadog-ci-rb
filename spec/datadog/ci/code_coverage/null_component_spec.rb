# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/code_coverage/null_component"

RSpec.describe Datadog::CI::CodeCoverage::NullComponent do
  subject(:component) { described_class.new }

  describe "#initialize" do
    it "sets enabled to false" do
      expect(component.enabled).to be false
    end
  end

  describe "#configure" do
    let(:library_configuration) do
      instance_double(Datadog::CI::Remote::LibrarySettings)
    end

    it "does nothing" do
      expect { component.configure(library_configuration) }.not_to raise_error
    end
  end

  describe "#upload" do
    let(:serialized_report) { '{"file.rb":[1,2,3]}' }
    let(:format) { "simplecov-internal" }

    it "returns nil" do
      expect(component.upload(serialized_report: serialized_report, format: format)).to be_nil
    end
  end

  describe "#shutdown!" do
    it "does nothing" do
      expect { component.shutdown! }.not_to raise_error
    end
  end
end
