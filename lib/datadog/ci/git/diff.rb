# frozen_string_literal: true

require "set"
require_relative "changed_lines"

module Datadog
  module CI
    module Git
      class Diff
        FILE_CHANGE_REGEX = /^diff --git a\/(?<file>.+?) b\//.freeze
        LINES_CHANGE_REGEX = /^@@ -\d+(?:,\d+)? \+(?<start>\d+)(?:,(?<count>\d+))? @@/.freeze
        DIFF_SCAN_REGEX = /^(?:diff --git a\/(.+?) b\/|@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@)/.freeze
        private_constant :DIFF_SCAN_REGEX

        def initialize(changed_files: {})
          @changed_files = changed_files # Hash of file_path => ChangedLines
        end

        # Check if any lines in the given range are changed for the specified file
        def lines_changed?(file_path, start_line: nil, end_line: nil)
          changed_lines = @changed_files[file_path]
          unless changed_lines
            Datadog.logger.debug { "No changes found for file: #{file_path}" }
            return false
          end

          # If either start_line or end_line is nil, return true if file is present
          return true if start_line.nil? || end_line.nil?

          changed_lines.overlaps?(start_line, end_line)
        end

        def empty?
          @changed_files.empty?
        end

        # for debug purposes
        def size
          @changed_files.size
        end

        # for debug purposes
        def inspect
          @changed_files.inspect
        end

        def self.parse_diff_output(output)
          return new if output.nil? || output.empty?

          changed_files = {}
          # @type var changed_files: Hash[String, ChangedLines]
          current_file = nil
          current_lines = nil
          # @type var current_lines: ChangedLines?

          output.scan(DIFF_SCAN_REGEX) do |changed_file, start_str, count_str|
            if changed_file.is_a?(String)
              unless changed_file.empty?
                current_file = changed_file
                current_lines = (changed_files[changed_file] ||= ChangedLines.new)
              end

              Datadog.logger.debug { "matched changed_file: #{changed_file}" }
            elsif start_str.is_a?(String) && current_lines
              start_line = start_str.to_i
              line_count = count_str ? count_str.to_i : 1
              end_line = start_line + line_count - 1

              current_lines.add_interval(start_line, end_line)

              Datadog.logger.debug { "Added interval [#{start_line}, #{end_line}] for file: #{current_file}" }
            end
          end

          new(changed_files: changed_files)
        end
      end
    end
  end
end
