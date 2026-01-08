# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/source_code/constant_resolver"

RSpec.describe Datadog::CI::SourceCode::ConstantResolver do
  describe ".resolve" do
    subject(:resolve) { described_class.resolve(constant_name) }

    context "with existing constant" do
      let(:constant_name) { "RSpec" }

      it "returns the source file path" do
        expect(resolve).to be_a(String)
        expect(resolve).to end_with(".rb")
      end
    end

    context "with nested constant" do
      let(:constant_name) { "RSpec::Core::Runner" }

      it "returns the source file path" do
        expect(resolve).to be_a(String)
        expect(resolve).to include("rspec")
      end
    end

    context "with non-existent constant" do
      let(:constant_name) { "NonExistentModule::DoesNotExist" }

      it "returns nil" do
        expect(resolve).to be_nil
      end
    end

    context "with built-in constant (defined in C)" do
      let(:constant_name) { "String" }

      it "returns nil (no source location for C-defined constants)" do
        expect(resolve).to be_nil
      end
    end

    context "with empty string" do
      let(:constant_name) { "" }

      it "returns nil" do
        expect(resolve).to be_nil
      end
    end

    context "with nil" do
      let(:constant_name) { nil }

      it "returns nil" do
        expect(resolve).to be_nil
      end
    end

    context "with integer" do
      let(:constant_name) { 123 }

      it "returns nil" do
        expect(resolve).to be_nil
      end
    end

    context "with malformed constant name" do
      let(:constant_name) { ":::" }

      it "returns nil without raising" do
        expect(resolve).to be_nil
      end
    end

    context "with constant that raises on lookup" do
      let(:constant_name) { "some invalid!! constant" }

      it "returns nil without raising" do
        expect(resolve).to be_nil
      end
    end
  end

  describe ".safely_get_const_source_location" do
    subject(:location) { described_class.safely_get_const_source_location(constant_name) }

    context "with existing constant" do
      let(:constant_name) { "RSpec" }

      it "returns [filename, lineno] array" do
        expect(location).to be_a(Array)
        expect(location.size).to eq(2)
        expect(location[0]).to be_a(String)
        expect(location[1]).to be_a(Integer)
      end
    end

    context "with constant that would raise exception" do
      let(:constant_name) { "invalid name!" }

      it "returns nil instead of raising" do
        expect { location }.not_to raise_error
        expect(location).to be_nil
      end
    end
  end
end
