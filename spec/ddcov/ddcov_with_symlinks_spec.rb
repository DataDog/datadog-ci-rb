# frozen_string_literal: true

require "fileutils"

require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::DDCov do
  before do
    # create a symlink to the calculator_with_symlinks/operations folder in vendor/gems
    FileUtils.ln_s(
      absolute_path("calculator_with_symlinks/operations"),
      absolute_path("calculator_with_symlinks/vendor/gems/operations"),
      force: true
    )

    require_relative "calculator_with_symlinks/calculator"
  end

  after do
    # delete symlink
    FileUtils.rm_f(
      absolute_path("calculator_with_symlinks/vendor/gems/operations")
    )
  end

  subject { described_class.new(root: root, threading_mode: :multi) }

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
