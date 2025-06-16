# frozen_string_literal: true

require "datadog/ci/git/changed_lines"

RSpec.describe Datadog::CI::Git::ChangedLines do
  subject(:changed_lines) { described_class.new }

  describe "#initialize" do
    it "creates an empty intervals array" do
      expect(changed_lines.intervals).to eq([])
    end

    it "is empty by default" do
      expect(changed_lines.empty?).to be true
    end
  end

  describe "#add_interval" do
    context "with valid intervals" do
      it "adds a single interval" do
        changed_lines.add_interval(1, 5)
        expect(changed_lines.intervals).to eq([[1, 5]])
      end

      it "adds multiple intervals" do
        changed_lines.add_interval(1, 5)
        changed_lines.add_interval(10, 15)
        expect(changed_lines.intervals).to eq([[1, 5], [10, 15]])
      end

      it "allows single-line intervals" do
        changed_lines.add_interval(5, 5)
        expect(changed_lines.intervals).to eq([[5, 5]])
      end

      it "allows adding intervals after build! and correctly merges them" do
        changed_lines.add_interval(1, 3)
        changed_lines.build! # Build first set
        expect(changed_lines.intervals).to eq([[1, 3]])

        # Adding more intervals should work and be included in next query
        changed_lines.add_interval(5, 7)
        expect(changed_lines.intervals).to eq([[1, 3], [5, 7]])
      end
    end

    context "with invalid intervals" do
      it "ignores intervals where start > end" do
        changed_lines.add_interval(10, 5)
        expect(changed_lines.intervals).to eq([])
      end

      it "ignores invalid intervals and preserves existing state" do
        changed_lines.add_interval(1, 3)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[1, 3]])

        # Adding invalid interval should not affect existing intervals
        changed_lines.add_interval(10, 5)
        expect(changed_lines.intervals).to eq([[1, 3]])
      end
    end

    context "with zero and negative line numbers" do
      it "handles zero start line" do
        changed_lines.add_interval(0, 5)
        expect(changed_lines.intervals).to eq([[0, 5]])
      end

      it "handles negative line numbers" do
        changed_lines.add_interval(-5, -1)
        expect(changed_lines.intervals).to eq([[-5, -1]])
      end

      it "handles mixed positive and negative" do
        changed_lines.add_interval(-2, 3)
        expect(changed_lines.intervals).to eq([[-2, 3]])
      end
    end
  end

  describe "#build!" do
    context "with empty intervals" do
      it "handles empty state correctly" do
        changed_lines.build!
        expect(changed_lines.intervals).to eq([])
        expect(changed_lines.empty?).to be true

        # Should be able to call build! multiple times safely
        changed_lines.build!
        expect(changed_lines.intervals).to eq([])
      end
    end

    context "with single interval" do
      it "keeps the interval as-is" do
        changed_lines.add_interval(5, 10)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[5, 10]])
      end
    end

    context "with non-overlapping intervals" do
      it "sorts intervals by start line" do
        changed_lines.add_interval(10, 15)
        changed_lines.add_interval(1, 5)
        changed_lines.add_interval(20, 25)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[1, 5], [10, 15], [20, 25]])
      end
    end

    context "with overlapping intervals" do
      it "merges completely overlapping intervals" do
        changed_lines.add_interval(1, 10)
        changed_lines.add_interval(3, 7)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[1, 10]])
      end

      it "merges partially overlapping intervals" do
        changed_lines.add_interval(1, 5)
        changed_lines.add_interval(3, 8)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[1, 8]])
      end

      it "merges multiple overlapping intervals" do
        changed_lines.add_interval(1, 3)
        changed_lines.add_interval(2, 5)
        changed_lines.add_interval(4, 7)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[1, 7]])
      end

      it "merges intervals that end at the same point" do
        changed_lines.add_interval(1, 5)
        changed_lines.add_interval(3, 5)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[1, 5]])
      end
    end

    context "with adjacent intervals" do
      it "merges adjacent intervals (end + 1 = start)" do
        changed_lines.add_interval(1, 5)
        changed_lines.add_interval(6, 10)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[1, 10]])
      end

      it "merges multiple adjacent intervals" do
        changed_lines.add_interval(1, 3)
        changed_lines.add_interval(4, 6)
        changed_lines.add_interval(7, 9)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[1, 9]])
      end
    end

    context "with complex scenarios" do
      it "handles mix of overlapping, adjacent, and separate intervals" do
        changed_lines.add_interval(15, 20)  # separate
        changed_lines.add_interval(1, 3)    # overlaps with next
        changed_lines.add_interval(2, 5)    # overlaps with previous, adjacent to next
        changed_lines.add_interval(6, 8)    # adjacent to previous
        changed_lines.add_interval(25, 30)  # separate
        changed_lines.add_interval(10, 12)  # separate

        changed_lines.build!
        expect(changed_lines.intervals).to eq([[1, 8], [10, 12], [15, 20], [25, 30]])
      end

      it "handles duplicate intervals" do
        changed_lines.add_interval(1, 5)
        changed_lines.add_interval(1, 5)
        changed_lines.add_interval(1, 5)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[1, 5]])
      end
    end

    context "already built" do
      it "is idempotent - multiple build! calls produce same result" do
        changed_lines.add_interval(10, 15)
        changed_lines.add_interval(1, 5)
        changed_lines.build!
        first_result = changed_lines.intervals

        # Multiple calls to build! should not change the result
        changed_lines.build!
        changed_lines.build!
        expect(changed_lines.intervals).to eq(first_result)
        expect(changed_lines.intervals).to eq([[1, 5], [10, 15]])
      end
    end

    context "with negative and zero line numbers" do
      it "properly sorts and merges negative intervals" do
        changed_lines.add_interval(-10, -5)
        changed_lines.add_interval(-7, -3)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[-10, -3]])
      end

      it "handles mix of negative, zero, and positive" do
        changed_lines.add_interval(-5, -1)
        changed_lines.add_interval(0, 3)
        changed_lines.add_interval(5, 10)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[-5, 3], [5, 10]])
      end
    end
  end

  describe "#overlaps?" do
    before do
      changed_lines.add_interval(5, 10)
      changed_lines.add_interval(15, 20)
      changed_lines.add_interval(25, 30)
    end

    context "with automatic building" do
      it "automatically builds when needed for queries" do
        # Use a fresh instance to avoid interference from before block
        fresh_lines = described_class.new

        # Add intervals out of order
        fresh_lines.add_interval(10, 15)
        fresh_lines.add_interval(1, 5)

        # overlaps? should automatically sort and merge before querying
        expect(fresh_lines.overlaps?(3, 12)).to be true # spans both intervals

        # Intervals should now be properly sorted
        expect(fresh_lines.intervals).to eq([[1, 5], [10, 15]])
      end
    end

    context "with empty intervals" do
      subject(:empty_changed_lines) { described_class.new }

      it "returns false for any query" do
        expect(empty_changed_lines.overlaps?(1, 10)).to be false
        expect(empty_changed_lines.overlaps?(0, 0)).to be false
      end
    end

    context "with invalid query ranges" do
      it "returns false when query_start > query_end" do
        expect(changed_lines.overlaps?(10, 5)).to be false
      end
    end

    context "with overlapping queries" do
      it "detects overlap at the beginning of an interval" do
        expect(changed_lines.overlaps?(3, 7)).to be true  # overlaps with [5, 10]
      end

      it "detects overlap at the end of an interval" do
        expect(changed_lines.overlaps?(8, 12)).to be true  # overlaps with [5, 10]
      end

      it "detects overlap when query completely contains an interval" do
        expect(changed_lines.overlaps?(4, 11)).to be true  # contains [5, 10]
      end

      it "detects overlap when query is completely contained in an interval" do
        expect(changed_lines.overlaps?(6, 9)).to be true  # contained in [5, 10]
      end

      it "detects exact match" do
        expect(changed_lines.overlaps?(5, 10)).to be true
        expect(changed_lines.overlaps?(15, 20)).to be true
      end

      it "detects single-line overlap at boundaries" do
        expect(changed_lines.overlaps?(5, 5)).to be true   # start of [5, 10]
        expect(changed_lines.overlaps?(10, 10)).to be true # end of [5, 10]
      end
    end

    context "with non-overlapping queries" do
      it "returns false for queries before all intervals" do
        expect(changed_lines.overlaps?(1, 3)).to be false
        expect(changed_lines.overlaps?(1, 4)).to be false
      end

      it "returns false for queries after all intervals" do
        expect(changed_lines.overlaps?(31, 35)).to be false
        expect(changed_lines.overlaps?(100, 200)).to be false
      end

      it "returns false for queries between intervals" do
        expect(changed_lines.overlaps?(11, 14)).to be false # between [5,10] and [15,20]
        expect(changed_lines.overlaps?(21, 24)).to be false # between [15,20] and [25,30]
      end

      it "returns false for adjacent non-overlapping queries" do
        expect(changed_lines.overlaps?(4, 4)).to be false   # just before [5, 10]
        expect(changed_lines.overlaps?(11, 11)).to be false # just after [5, 10]
      end
    end

    context "with edge cases for binary search" do
      subject(:single_interval_lines) do
        lines = described_class.new
        lines.add_interval(10, 15)
        lines
      end

      it "handles single interval correctly" do
        expect(single_interval_lines.overlaps?(5, 8)).to be false
        expect(single_interval_lines.overlaps?(8, 12)).to be true
        expect(single_interval_lines.overlaps?(12, 17)).to be true
        expect(single_interval_lines.overlaps?(17, 20)).to be false
      end

      it "works with queries at exact boundaries" do
        expect(single_interval_lines.overlaps?(10, 15)).to be true
        expect(single_interval_lines.overlaps?(9, 10)).to be true
        expect(single_interval_lines.overlaps?(15, 16)).to be true
        expect(single_interval_lines.overlaps?(9, 9)).to be false
        expect(single_interval_lines.overlaps?(16, 16)).to be false
      end
    end

    context "with large number of intervals (performance test)" do
      subject(:many_intervals_lines) do
        lines = described_class.new
        # Create 1000 non-overlapping intervals: [0,0], [10,10], [20,20], ..., [9990,9990]
        1000.times { |i| lines.add_interval(i * 10, i * 10) }
        lines
      end

      it "efficiently finds overlaps in large dataset" do
        # Test various positions
        expect(many_intervals_lines.overlaps?(0, 0)).to be true     # first
        expect(many_intervals_lines.overlaps?(5000, 5000)).to be true  # middle
        expect(many_intervals_lines.overlaps?(9990, 9990)).to be true  # last
        expect(many_intervals_lines.overlaps?(5, 5)).to be false    # gap
        expect(many_intervals_lines.overlaps?(10000, 10000)).to be false # after all
      end
    end

    context "with negative line numbers" do
      subject(:negative_lines) do
        lines = described_class.new
        lines.add_interval(-10, -5)
        lines.add_interval(0, 5)
        lines
      end

      it "handles negative line numbers correctly" do
        expect(negative_lines.overlaps?(-12, -8)).to be true   # overlaps [-10, -5]
        expect(negative_lines.overlaps?(-15, -11)).to be false # before [-10, -5]
        expect(negative_lines.overlaps?(-3, 2)).to be true     # spans both intervals
      end
    end
  end

  describe "#empty?" do
    it "returns true for new instance" do
      expect(changed_lines.empty?).to be true
    end

    it "returns false after adding intervals" do
      changed_lines.add_interval(1, 5)
      expect(changed_lines.empty?).to be false
    end

    it "returns true after adding only invalid intervals" do
      changed_lines.add_interval(10, 5) # invalid: start > end
      expect(changed_lines.empty?).to be true
    end
  end

  describe "#intervals" do
    it "returns empty array for new instance" do
      expect(changed_lines.intervals).to eq([])
    end

    it "returns copy of intervals, not the original array" do
      changed_lines.add_interval(1, 5)
      intervals = changed_lines.intervals
      intervals << [10, 15]

      # Original should not be modified
      expect(changed_lines.intervals).to eq([[1, 5]])
    end

    it "automatically builds when intervals() is called" do
      changed_lines.add_interval(10, 15)
      changed_lines.add_interval(1, 5)

      # Should automatically sort when intervals() is called
      intervals = changed_lines.intervals
      expect(intervals).to eq([[1, 5], [10, 15]])
    end

    it "returns sorted and merged intervals" do
      changed_lines.add_interval(10, 15)
      changed_lines.add_interval(1, 5)
      changed_lines.add_interval(4, 8)

      expect(changed_lines.intervals).to eq([[1, 8], [10, 15]])
    end
  end

  # Test potential bug scenarios
  describe "potential bug scenarios" do
    context "integer overflow protection" do
      it "handles very large line numbers" do
        large_num = 2**30
        changed_lines.add_interval(large_num, large_num + 10)
        expect(changed_lines.intervals).to eq([[large_num, large_num + 10]])
        expect(changed_lines.overlaps?(large_num + 5, large_num + 15)).to be true
      end
    end

    context "binary search edge cases" do
      it "handles correct binary search when all intervals are to the left" do
        changed_lines.add_interval(1, 5)
        changed_lines.add_interval(10, 15)
        expect(changed_lines.overlaps?(20, 25)).to be false
      end

      it "handles correct binary search when all intervals are to the right" do
        changed_lines.add_interval(10, 15)
        changed_lines.add_interval(20, 25)
        expect(changed_lines.overlaps?(1, 5)).to be false
      end

      it "handles binary search convergence correctly" do
        # Create scenario that could cause infinite loop if binary search is wrong
        changed_lines.add_interval(1, 1)
        changed_lines.add_interval(3, 3)
        changed_lines.add_interval(5, 5)
        expect(changed_lines.overlaps?(2, 2)).to be false
        expect(changed_lines.overlaps?(4, 4)).to be false
      end
    end

    context "build behavior edge cases" do
      it "handles rebuilding after adding intervals post-build" do
        changed_lines.add_interval(10, 15)
        changed_lines.build!
        expect(changed_lines.intervals).to eq([[10, 15]])

        changed_lines.add_interval(1, 5)
        expect(changed_lines.intervals).to eq([[1, 5], [10, 15]])
      end

      it "preserves correct behavior when mixing build! calls and queries" do
        changed_lines.add_interval(10, 15)
        changed_lines.build!

        changed_lines.add_interval(1, 5)
        expect(changed_lines.overlaps?(3, 12)).to be true

        changed_lines.add_interval(6, 9) # This should merge with others
        expect(changed_lines.intervals).to eq([[1, 15]])
      end
    end
  end
end
