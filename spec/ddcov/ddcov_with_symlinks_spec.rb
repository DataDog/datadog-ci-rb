# frozen_string_literal: true

require "datadog_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

require_relative "calculator_with_symlinks/calculator"

RSpec.describe Datadog::CI::ITR::Coverage::DDCov do
  def absolute_path(path)
    File.expand_path(File.join(__dir__, path))
  end

  subject { described_class.new(root: root) }

  describe "code coverage collection" do
    let!(:calculator) { Calculator.new }

    context "when root is the calculator project dir" do
      let(:root) { absolute_path("calculator_with_symlinks") }

      it "collects code coverage including Calculator and operations" do
        subject.start

        expect(calculator.add(1, 2)).to eq(3)
        expect(calculator.subtract(1, 2)).to eq(-1)

        coverage = subject.stop

        expect(coverage.size).to eq(3)
        expect(coverage.keys).to include(
          absolute_path("calculator_with_symlinks/calculator.rb"),
          absolute_path("calculator_with_symlinks/operations/add.rb"),
          absolute_path("calculator_with_symlinks/operations/subtract.rb")
        )
      end
    end
  end
end
