# frozen_string_literal: true

require "spec_helper"
require "datadog/ci/source_code/iseq_hash"

RSpec.describe Datadog::CI::SourceCode do
  describe ".iseq_hash" do
    let(:hex_hash_pattern) { /\A[0-9a-f]{16}\z/ }

    def build_proc(source, file: "hash_spec.rb", line: 1)
      RubyVM::InstructionSequence.compile(source, file, file, line).eval
    end

    it "returns a compact hex hash for a Proc" do
      hash = described_class.iseq_hash(proc { 1 + 1 })

      expect(hash).to match(hex_hash_pattern)
    end

    it "returns an empty string for nil" do
      expect(described_class.iseq_hash(nil)).to eq("")
    end

    it "returns an empty string for C-backed methods without an instruction sequence" do
      expect(described_class.iseq_hash(String.instance_method(:upcase))).to eq("")
    end

    it "does not read source files" do
      expect(File).not_to receive(:read)
      expect(File).not_to receive(:readlines)

      described_class.iseq_hash(proc { "no disk please" })
    end

    it "returns the same hash for the same body compiled at different file paths and lines" do
      first_proc = build_proc("proc { 41 + 1 }", file: "first_spec.rb", line: 10)
      second_proc = build_proc("proc { 41 + 1 }", file: "second_spec.rb", line: 250)

      expect(described_class.iseq_hash(first_proc)).to eq(described_class.iseq_hash(second_proc))
    end

    it "returns the same hash for nested blocks compiled at different file paths and lines" do
      first_proc = build_proc(
        "proc { [1, 2, 3].map { |value| value * 2 } }",
        file: "first_nested_spec.rb",
        line: 10
      )
      second_proc = build_proc(
        "proc { [1, 2, 3].map { |value| value * 2 } }",
        file: "second_nested_spec.rb",
        line: 250
      )

      expect(described_class.iseq_hash(first_proc)).to eq(described_class.iseq_hash(second_proc))
    end

    it "returns different hashes when a literal changes" do
      first_proc = proc { 41 + 1 }
      second_proc = proc { 41 + 2 }

      expect(described_class.iseq_hash(first_proc)).not_to eq(described_class.iseq_hash(second_proc))
    end

    it "returns different hashes when the invoked method changes" do
      first_proc = proc { "abc".upcase }
      second_proc = proc { "abc".downcase }

      expect(described_class.iseq_hash(first_proc)).not_to eq(described_class.iseq_hash(second_proc))
    end

    it "returns different hashes when nested block logic changes" do
      first_proc = proc { [1, 2, 3].map { |value| value * 2 } }
      second_proc = proc { [1, 2, 3].map { |value| value * 3 } }

      expect(described_class.iseq_hash(first_proc)).not_to eq(described_class.iseq_hash(second_proc))
    end

    it "returns different hashes when local variable names change" do
      first_proc = proc {
        result = 42
        result
      }
      second_proc = proc {
        value = 42
        value
      }

      expect(described_class.iseq_hash(first_proc)).not_to eq(described_class.iseq_hash(second_proc))
    end

    it "returns different hashes when block parameter names change" do
      first_proc = proc { |result| result }
      second_proc = proc { |value| value }

      expect(described_class.iseq_hash(first_proc)).not_to eq(described_class.iseq_hash(second_proc))
    end

    it "supports Method objects" do
      klass = Class.new do
        def calculate
          41 + 1
        end
      end

      hash = described_class.iseq_hash(klass.new.method(:calculate))

      expect(hash).to match(hex_hash_pattern)
    end

    it "supports UnboundMethod objects" do
      klass = Class.new do
        def calculate
          41 + 1
        end
      end

      hash = described_class.iseq_hash(klass.instance_method(:calculate))

      expect(hash).to match(hex_hash_pattern)
    end

    it "supports InstructionSequence objects directly" do
      iseq = RubyVM::InstructionSequence.of(proc { 41 + 1 })

      expect(described_class.iseq_hash(iseq)).to match(hex_hash_pattern)
    end

    it "returns the same hash for an InstructionSequence and its original Proc" do
      target = proc { 41 + 1 }
      iseq = RubyVM::InstructionSequence.of(target)

      expect(described_class.iseq_hash(iseq)).to eq(described_class.iseq_hash(target))
    end

    it "normalizes hashes deterministically" do
      first_proc = build_proc("proc { {a: 1, b: 2} }", file: "first_hash_spec.rb", line: 10)
      second_proc = build_proc("proc { {a: 1, b: 2} }", file: "second_hash_spec.rb", line: 300)

      expect(described_class.iseq_hash(first_proc)).to eq(described_class.iseq_hash(second_proc))
    end

    it "includes regular expression body differences" do
      first_proc = proc { /abc/i.match?("ABC") }
      second_proc = proc { /abc/.match?("ABC") }

      expect(described_class.iseq_hash(first_proc)).not_to eq(described_class.iseq_hash(second_proc))
    end

    it "warns and returns an empty string when Ruby cannot extract an instruction sequence" do
      allow(RubyVM::InstructionSequence).to receive(:of).and_raise(StandardError, "boom")

      expect(Datadog.logger).to receive(:warn).and_yield
      expect(described_class.iseq_hash(proc { 1 })).to eq("")
    end

    it "falls back to Kernel.warn when the Datadog logger cannot warn" do
      allow(RubyVM::InstructionSequence).to receive(:of).and_raise(StandardError, "boom")
      allow(Datadog.logger).to receive(:warn).and_raise(StandardError, "logger boom")

      expect(Kernel).to receive(:warn).with("Unable to compute Ruby ISeq hash: StandardError: boom")
      expect(described_class.iseq_hash(proc { 1 })).to eq("")
    end

    it "returns an empty string even when all warning paths fail" do
      allow(RubyVM::InstructionSequence).to receive(:of).and_raise(StandardError, "boom")
      allow(Datadog.logger).to receive(:warn).and_raise(StandardError, "logger boom")
      allow(Kernel).to receive(:warn).and_raise(StandardError, "stderr boom")

      expect(described_class.iseq_hash(proc { 1 })).to eq("")
    end

    it "warns and returns an empty string when ISeq serialization fails" do
      target = proc { 1 }
      iseq = instance_double(RubyVM::InstructionSequence)

      allow(RubyVM::InstructionSequence).to receive(:of).with(target).and_return(iseq)
      allow(iseq).to receive(:to_a).and_raise(StandardError, "cannot serialize")

      expect(Datadog.logger).to receive(:warn).and_yield
      expect(described_class.iseq_hash(target)).to eq("")
    end

    it "warns and returns an empty string when native hashing fails" do
      skip "native ISeq hash is not available" unless described_class::ISEQ_HASH_NATIVE_AVAILABLE

      target = proc { 1 }

      allow(described_class).to receive(:_native_iseq_hash).with(target).and_raise(StandardError, "native boom")

      expect(Datadog.logger).to receive(:warn).and_yield
      expect(described_class.iseq_hash(target)).to eq("")
    end

    it "warns and returns an empty string when fallback hashing fails" do
      target = proc { 1 }

      stub_const("Datadog::CI::SourceCode::ISEQ_HASH_NATIVE_AVAILABLE", false)
      allow(Marshal).to receive(:dump).and_raise(StandardError, "cannot dump")

      expect(Datadog.logger).to receive(:warn).and_yield
      expect(described_class.iseq_hash(target)).to eq("")
    end
  end
end
