# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/contrib/rspec/anonymous_example_name"

RSpec.describe Datadog::CI::Contrib::RSpec::AnonymousExampleName do
  describe ".call" do
    it "renders an expect-to matcher without dynamic object inspection" do
      name = described_class.call(proc { expect(described_class.active).to eq(context) })

      expect(name).to eq("is expected to eq context")
    end

    it "renders Object.new matcher arguments as class names" do
      name = described_class.call(proc { expect(Object.new).to eq(Object.new) })

      expect(name).to eq("is expected to eq Object")
    end

    it "renders class constants" do
      name = described_class.call(proc { expect(Object).to eq(Object) })

      expect(name).to eq("is expected to eq Object")
    end

    it "renders nil predicate matchers" do
      name = described_class.call(proc { expect(nil).to be_nil })

      expect(name).to eq("is expected to be nil")
    end

    it "renders negated matchers" do
      name = described_class.call(proc { expect(["foo"]).not_to include("bar") })

      expect(name).to eq("is expected not to include \"bar\"")
    end

    it "renders is_expected matchers" do
      name = described_class.call(proc { is_expected.to be_empty })

      expect(name).to eq("is expected to be empty")
    end

    it "renders should-syntax matchers" do
      name = described_class.call(proc { should eq([]) })

      expect(name).to eq("is expected to eq []")
    end

    it "renders literal matcher arguments" do
      name = described_class.call(proc { expect({b: 2, a: 1}).to eq({a: 1, b: 2}) })

      expect(name).to eq("is expected to eq {:a => 1, :b => 2}")
    end

    it "renders comparison matchers" do
      name = described_class.call(proc { expect(1).to be > 0 })

      expect(name).to eq("is expected to be > 0")
    end

    it "renders block matchers" do
      name = described_class.call(proc { expect { raise "boom" }.to raise_error(RuntimeError) })

      expect(name).to eq("is expected to raise error RuntimeError")
    end

    it "renders matcher chains" do
      name = described_class.call(proc { expect { 1 + 1 }.to change { 2 + 2 }.by(0) })

      expect(name).to eq("is expected to change by 0")
    end

    it "returns nil for non-matcher anonymous examples" do
      expect(described_class.call(proc { 1 + 1 })).to be_nil
    end

    it "returns nil for non-RSpec to calls" do
      expect(described_class.call(proc { value.to eq(1) })).to be_nil
    end

    it "returns nil for nil" do
      expect(described_class.call(nil)).to be_nil
    end

    it "warns and returns nil when Ruby cannot extract an instruction sequence" do
      target = proc { expect(1).to eq(1) }

      allow(RubyVM::InstructionSequence).to receive(:of).with(target).and_raise(StandardError, "boom")

      expect(Datadog.logger).to receive(:warn).and_yield
      expect(described_class.call(target)).to be_nil
    end
  end
end
