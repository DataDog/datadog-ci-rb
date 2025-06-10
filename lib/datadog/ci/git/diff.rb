# frozen_string_literal: true

require "set"
require_relative "changed_lines"

module Datadog
  module CI
    module Git
      class Diff
        FILE_CHANGE_REGEX = /^diff --git a\/(?<file>.+?) b\//.freeze
        LINES_CHANGE_REGEX = /^@@ -\d+(?:,\d+)? \+(?<start>\d+)(?:,(?<count>\d+))? @@/.freeze

        def initialize(changed_files: {})
          @changed_files = changed_files # Hash of file_path => ChangedLines
        end

        def include?(file_path)
          @changed_files.key?(file_path)
        end

        # Check if any lines in the given range are changed for the specified file
        def lines_changed?(file_path, start_line, end_line)
          changed_lines = @changed_files[file_path]
          return false unless changed_lines

          changed_lines.overlaps?(start_line, end_line)
        end

        # Get all changed line intervals for a file
        def changed_line_intervals(file_path)
          changed_lines = @changed_files[file_path]
          return [] unless changed_lines

          changed_lines.intervals
        end

        def size
          @changed_files.size
        end

        def empty?
          @changed_files.empty?
        end

        def inspect
          @changed_files.inspect
        end

        def self.parse_diff_output(output)
          return new if output.nil? || output.empty?

          changed_files = {}
          current_file = nil

          output.each_line do |line|
            # Match lines like: diff --git a/foo/bar.rb b/foo/bar.rb
            # This captures git changes on file level
            match = FILE_CHANGE_REGEX.match(line)
            if match && match[:file]
              changed_file = match[:file]
              # Normalize to repo root
              normalized_changed_file = LocalRepository.relative_to_root(changed_file)

              unless normalized_changed_file.nil? || normalized_changed_file.empty?
                current_file = normalized_changed_file
                p current_file
                changed_files[current_file] ||= ChangedLines.new
              end

              Datadog.logger.debug { "matched changed_file: #{changed_file} from line: #{line}" }
              Datadog.logger.debug { "normalized_changed_file: #{normalized_changed_file}" }

              next
            end

            # Match lines like: @@ -1,2 +3,4 @@
            match = LINES_CHANGE_REGEX.match(line)
            if match && match[:start] && current_file
              start_line = match[:start].to_i

              line_count = 1 # Default to 1 line if count not specified
              line_count = match[:count].to_i if match[:count]

              end_line = start_line + line_count - 1

              changed_files[current_file].add_interval(start_line, end_line)

              Datadog.logger.debug { "Added interval [#{start_line}, #{end_line}] for file: #{current_file}" }
            end
          end

          new(changed_files: changed_files)
        end
      end
    end
  end
end
