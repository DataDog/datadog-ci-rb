# frozen_string_literal: true

require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::DDCov, "collector lifetimes" do
  let(:root) { File.expand_path(__dir__) }
  let(:mode) { :multi }
  let(:first) { described_class.new(root: root, threading_mode: mode, use_allocation_tracing: false) }
  let(:second) { described_class.new(root: root, threading_mode: mode, use_allocation_tracing: false) }

  after do
    first.stop
    second.stop
  end

  [:multi, :single].each do |mode|
    context "in #{mode} mode" do
      let(:mode) { mode }

      it "does not stop another collector when one finishes" do
        first.start
        second.start
        first.stop
        # A distinct loaded fixture must be observed after the first stop.
        load File.join(root, "calculator", "operations", "add.rb")
        expect(second.stop.keys).to include(File.join(root, "calculator", "operations", "add.rb"))
      end

      it "can be stopped repeatedly, including before it starts" do
        expect(first.stop).to eq({})
        first.start
        first.stop
        expect(first.stop).to eq({})
      end
    end
  end

  context "with a worker thread" do
    let(:mode) { :single }

    it "allows the coordinator to release unfinished worker coverage" do
      Thread.new do
        first.start
        expect(1 + 2).to eq(3)
      end.join
      expect(first.stop.keys).to include(__FILE__)
      expect(first.stop).to eq({})
    end
  end
end
