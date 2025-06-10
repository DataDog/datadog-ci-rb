# frozen_string_literal: true

module Datadog
  module CI
    module Git
      # Helper class to efficiently store and query changed line intervals for a single file
      # Uses merged sorted intervals with binary search for O(log n) query performance
      class ChangedLines
        def initialize
          @intervals = [] # Array of [start, end] pairs
          @built = false
        end

        # Add an interval (defers merging until build! is called)
        def add_interval(start_line, end_line)
          return if start_line > end_line

          @intervals << [start_line, end_line]
          @built = false
        end

        # Sort and merge all intervals
        # Call this after all intervals have been added
        def build!
          return false if @built

          @built = true
          return false if @intervals.empty?

          # Sort intervals by start line
          @intervals.sort_by!(&:first)

          # Merge overlapping intervals
          merged = []

          # @type var current_start: Integer
          # @type var current_end: Integer
          current_start, current_end = @intervals.first

          @intervals.each_with_index do |interval, index|
            next if index == 0
            # @type var start_line: Integer
            # @type var end_line: Integer
            start_line, end_line = interval

            if start_line <= current_end + 1
              # Overlapping or adjacent intervals, merge them
              current_end = [current_end, end_line].max
            else
              # Non-overlapping interval, save current and start new
              merged << [current_start, current_end]
              current_start = start_line
              current_end = end_line
            end
          end

          # Don't forget the last interval
          merged << [current_start, current_end]

          @intervals = merged
          true
        end

        # Check if any line in the query interval overlaps with changed lines
        # Uses binary search for O(log n) performance
        def overlaps?(query_start, query_end)
          build! unless @built

          return false if @intervals.empty? || query_start > query_end

          # Binary search for the first interval that might overlap
          left = 0
          right = @intervals.length - 1

          while left <= right
            mid = (left + right) / 2
            # @type var interval_start: Integer
            # @type var interval_end: Integer
            interval_start, interval_end = @intervals[mid]

            if interval_end < query_start
              left = mid + 1
            elsif interval_start > query_end
              right = mid - 1
            else
              # Found overlap
              return true
            end
          end

          false
        end

        def empty?
          @intervals.empty?
        end

        def intervals
          build! unless @built
          @intervals.dup
        end
      end
    end
  end
end
