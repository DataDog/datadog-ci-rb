# frozen_string_literal: true

require "set"
require_relative "../../../lib/datadog/ci/git/changed_lines"

# A byte stream represents interleaved additions, builds and overlap queries.
# The oracle enumerates line numbers: it shares neither merging nor binary
# search with the implementation. Bounds keep each input cheap and reproducible.
module ChangedLinesTarget
  def self.check(data)
    lines = Datadog::CI::Git::ChangedLines.new
    model = Set.new

    data.bytes.first(384).each_slice(3) do |operation, first, last|
      start_line = (first || 0) - 128
      end_line = (last || 0) - 128

      case operation % 3
      when 0
        lines.add_interval(start_line, end_line)
        model.merge(start_line..end_line)
      when 1
        expected = (start_line..end_line).any? { |line| model.include?(line) }
        actual = lines.overlaps?(start_line, end_line)
        raise "overlap mismatch: #{[start_line, end_line, expected, actual].inspect}" unless actual == expected
      when 2
        lines.build!
      end

      raise "empty? mismatch" unless lines.empty? == model.empty?
    end

    actual_lines = lines.intervals.flat_map { |first, last| (first..last).to_a }
    raise "merged intervals mismatch" unless actual_lines == model.to_a.sort

    lines.intervals.each_cons(2) do |left, right|
      raise "intervals are not canonical" unless left.last + 1 < right.first
    end

    true
  end
end
