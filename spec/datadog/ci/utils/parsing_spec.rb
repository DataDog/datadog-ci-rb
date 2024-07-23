# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/utils/parsing"

RSpec.describe Datadog::CI::Utils::Parsing do
  describe ".convert_to_bool" do
    subject(:convert_to_bool) { described_class.convert_to_bool(value) }

    context "when the value is a boolean" do
      context "and the value is true" do
        let(:value) { true }

        it { is_expected.to be true }
      end

      context "and the value is false" do
        let(:value) { false }

        it { is_expected.to be false }
      end
    end

    context "when the value is a string" do
      context "and the value is 'true'" do
        let(:value) { "true" }

        it { is_expected.to be true }
      end

      context "and the value is 'false'" do
        let(:value) { "false" }

        it { is_expected.to be false }
      end

      context "and the value is '1'" do
        let(:value) { "1" }

        it { is_expected.to be true }
      end

      context "and the value is '0'" do
        let(:value) { "0" }

        it { is_expected.to be false }
      end

      context "and the value is 'TRUE'" do
        let(:value) { "TRUE" }

        it { is_expected.to be true }
      end

      context "and the value is 'FALSE'" do
        let(:value) { "FALSE" }

        it { is_expected.to be false }
      end
    end

    context "when the value is an integer" do
      context "and the value is 1" do
        let(:value) { 1 }

        it { is_expected.to be true }
      end

      context "and the value is 0" do
        let(:value) { 0 }

        it { is_expected.to be false }
      end
    end
  end
end
