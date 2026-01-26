# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/test_impact_analysis/skippable_percentage/calculator"

RSpec.describe Datadog::CI::TestImpactAnalysis::SkippablePercentage::Calculator do
  let(:rspec_cli_options) { [] }
  let(:verbose) { false }
  let(:spec_path) { "spec/datadog/ci/test_impact_analysis/skippable_percentage/fixture_spec" }

  let(:calculator) { described_class.new(rspec_cli_options: rspec_cli_options, verbose: verbose, spec_path: spec_path) }

  before do
    FileUtils.mkdir_p(spec_path)

    File.write(File.join(spec_path, "first_spec.rb"), <<~SPEC)
      RSpec.describe 'FirstSpec' do
        it 'test 1' do
        end

        it 'test 2' do
        end

        it 'test 3' do
        end
      end
    SPEC
  end

  after do
    FileUtils.rm_rf(spec_path)
  end

  describe "#call" do
    subject(:call) { calculator.call }

    include_context "CI mode activated" do
      let(:integration_name) { :rspec }
      let(:itr_enabled) { true }
      let(:tests_skipping_enabled) { true }

      let(:itr_skippable_tests) do
        Set.new([
          "FirstSpec at ./spec/datadog/ci/test_impact_analysis/skippable_percentage/fixture_spec/first_spec.rb.test 1.{\"arguments\":{},\"metadata\":{\"scoped_id\":\"1:1\"}}",
          "FirstSpec at ./spec/datadog/ci/test_impact_analysis/skippable_percentage/fixture_spec/first_spec.rb.test 7.{\"arguments\":{},\"metadata\":{\"scoped_id\":\"1:1\"}}"
        ])
      end
    end

    it "returns the skippable percentage" do
      with_new_rspec_environment do
        expect(call).to be_within(0.01).of(0.33)
        expect(calculator.failed).to be false
      end
    end
  end
end
