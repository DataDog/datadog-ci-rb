# frozen_string_literal: true

require "prop_check"
require "set"
require "datadog/ci/git/changed_lines"
require_relative "../../../support/fuzz/changed_lines_target"

RSpec.describe Datadog::CI::Git::ChangedLines do
  it "matches a set of changed lines across generated operation sequences" do
    generators = PropCheck::Generators
    bytes = generators.array(generators.choose(0..255), max: 96)
    rng = Random.new(RSpec.configuration.seed)
    seeded = PropCheck::Generator.new { |**options| bytes.generate(**options.merge(rng: rng)) }

    PropCheck.forall(seeded).with_config(n_runs: 300).check do |input|
      expect(ChangedLinesTarget.check(input.pack("C*"))).to be true
    end
  end

  it "preserves inclusive overlap semantics after translating coordinates by a large integer" do
    generators = PropCheck::Generators
    pair = generators.tuple(generators.choose(-20..20), generators.choose(-20..20))
    cases = generators.tuple(generators.array(pair, max: 20), pair)
    rng = Random.new(RSpec.configuration.seed)
    seeded = PropCheck::Generator.new { |**options| cases.generate(**options.merge(rng: rng)) }

    PropCheck.forall(seeded).with_config(n_runs: 200).check do |intervals, query|
      model = Set.new(intervals.flat_map { |first, last| (first..last).to_a })
      expected = (query.first..query.last).any? { |line| model.include?(line) }

      [0, 2**64, -(2**64)].each do |offset|
        lines = described_class.new
        intervals.each { |first, last| lines.add_interval(first + offset, last + offset) }
        expect(lines.overlaps?(query.first + offset, query.last + offset)).to eq(expected)
        # Point queries check both inclusive endpoints and the immediately adjacent gaps.
        intervals.flatten.each do |endpoint|
          [endpoint - 1, endpoint, endpoint + 1].each do |line|
            expect(lines.overlaps?(line + offset, line + offset)).to eq(model.include?(line))
          end
        end
      end
    end
  end

  it "replays the checked-in fuzz corpus" do
    corpus = Dir[File.expand_path("../../../support/fuzz/corpus/*", __dir__)].sort
    expect(corpus).not_to be_empty
    corpus.each do |path|
      expect(ChangedLinesTarget.check(File.binread(path))).to be true
    end
  end
end
