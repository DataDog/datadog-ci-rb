# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/contrib/rspec/anonymous_example_name"

RSpec.describe Datadog::CI::Contrib::RSpec::AnonymousExampleName do
  def iseq_with_body(body)
    double(to_a: Array.new(14).tap { |data| data[13] = body })
  end

  describe ".supported?" do
    it "is enabled on Ruby versions with supported instruction sequence shapes" do
      expected = RUBY_ENGINE == "ruby" && Gem::Version.new(RUBY_VERSION) >= described_class::MINIMUM_RUBY_VERSION

      expect(described_class.supported?).to eq(expected)
    end
  end

  describe ".call" do
    context "when Ruby bytecode is supported" do
      before do
        skip "anonymous example names require Ruby #{described_class::MINIMUM_RUBY_VERSION}+" unless described_class.supported?
      end

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

      it "renders less common literal matcher arguments" do
        examples = {
          proc { expect(1).to eq(nil) } => "is expected to eq nil",
          proc { expect(1).to eq(true) } => "is expected to eq true",
          proc { expect(1).to eq(false) } => "is expected to eq false",
          proc { expect(1).to eq(:ok) } => "is expected to eq :ok",
          proc { expect([:ok]).to eq([:ok]) } => "is expected to eq [:ok]",
          proc { expect("foo").to match(/foo/) } => "is expected to match /foo/"
        }

        examples.each do |target, expected_name|
          expect(described_class.call(target)).to eq(expected_name)
        end
      end

      it "renders dynamic hash matcher arguments without object inspection" do
        key = :left
        value = 2

        name = described_class.call(proc { expect(1).to eq({key => value}) })

        expect(name).to eq("is expected to eq {local => local}")
      end

      it "renders method calls inside matcher arguments" do
        key = :left

        name = described_class.call(proc { expect(1).to eq(key.to_s) })

        expect(name).to eq("is expected to eq local.to_s")
      end

      it "trims long literal matcher arguments" do
        name = described_class.call(
          proc {
            expect(1).to eq("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
          }
        )

        expect(name).to eq("is expected to eq \"#{"x" * 76}...")
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

      it "does not evaluate explosive subject code while naming examples" do
        bomb = Object.new
        bomb.define_singleton_method(:explode) { raise "boom" }

        direct_subject_name = described_class.call(proc { expect(bomb.explode).to eq(1) })
        block_subject_name = described_class.call(proc { expect { bomb.explode }.to raise_error(RuntimeError) })

        expect(direct_subject_name).to eq("is expected to eq 1")
        expect(block_subject_name).to eq("is expected to raise error RuntimeError")
      end
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

    it "returns nil when Ruby bytecode is not supported" do
      allow(described_class).to receive(:supported?).and_return(false)

      expect(described_class.call(proc { expect(1).to eq(1) })).to be_nil
    end

    it "returns nil for incomplete instruction sequence data" do
      allow(described_class).to receive(:supported?).and_return(true)

      targets = [
        [proc {}, iseq_with_body(nil)],
        [proc {}, iseq_with_body([:event, :label, [:unknown_opcode]])],
        [proc {}, iseq_with_body([[:putself], [:opt_send_without_block, {mid: :to, orig_argc: 1}]])]
      ]
      targets.each do |target, iseq|
        allow(RubyVM::InstructionSequence).to receive(:of).with(target).and_return(iseq)
      end

      expect(Datadog.logger).not_to receive(:warn)
      targets.each do |target, _iseq|
        expect(described_class.call(target)).to be_nil
      end
    end

    it "warns and returns nil when malformed instruction sequence data raises while rendering" do
      allow(described_class).to receive(:supported?).and_return(true)

      bad_argument_count = Object.new
      targets = [
        [proc {}, double(to_a: nil)],
        [proc {}, double(to_a: Object.new)],
        [proc {}, iseq_with_body([[:opt_send_without_block, {mid: :to, orig_argc: bad_argument_count}]])],
        [
          proc {},
          iseq_with_body([
            [:putself],
            [:newarray, bad_argument_count],
            [:opt_send_without_block, {mid: :to, orig_argc: 1}]
          ])
        ]
      ]
      targets.each do |target, iseq|
        allow(RubyVM::InstructionSequence).to receive(:of).with(target).and_return(iseq)
      end

      expect(Datadog.logger).to receive(:warn).exactly(targets.length).times.and_yield
      targets.each do |target, _iseq|
        expect(described_class.call(target)).to be_nil
      end
    end

    it "warns and returns nil when Ruby cannot extract an instruction sequence" do
      target = proc { expect(1).to eq(1) }

      allow(described_class).to receive(:supported?).and_return(true)
      allow(RubyVM::InstructionSequence).to receive(:of).with(target).and_raise(StandardError, "boom")

      expect(Datadog.logger).to receive(:warn).and_yield
      expect(described_class.call(target)).to be_nil
    end
  end
end
