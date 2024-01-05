# frozen_string_literal: true

require_relative "rule"

module Datadog
  module CI
    module Codeowners
      # Responsible for matching a test source file path to a list of owners
      class Matcher
        def initialize(codeowners_file_path)
          @rules = parse(codeowners_file_path)
          @rules.reverse!
        end

        def list_owners(file_path)
          # treat all file paths that we check as absolute from the repository root
          file_path = "/#{file_path}" unless file_path.start_with?("/")

          @rules.each do |rule|
            return rule.owners if rule.match?(file_path)
          end

          nil
        end

        private

        def parse(file_path)
          return [] unless File.exist?(file_path)

          result = []

          File.open(file_path, "r") do |f|
            f.each_line do |line|
              line.strip!

              # Skip comments, empty lines, and section lines
              next if line.empty?
              next if comment?(line)
              next if section?(line)

              pattern, *line_owners = line.strip.split(/\s+/)
              next if pattern.nil? || pattern.empty?

              pattern = expand_pattern(pattern)

              result << Rule.new(pattern, line_owners)
            end
          end

          result
        end

        def comment?(line)
          line.start_with?("#")
        end

        def section?(line)
          line.start_with?("[", "^[") && line.end_with?("]")
        end

        def expand_pattern(pattern)
          return pattern if pattern == "*"

          # if pattern ends with a slash then it matches everything deeply nested in this directory
          pattern += "**" if pattern.end_with?(::File::SEPARATOR)

          # if pattern doesn't start with a slash then it matches anywhere in the repository
          if !pattern.start_with?(::File::SEPARATOR, "**#{::File::SEPARATOR}", "*#{::File::SEPARATOR}")
            pattern = "**#{::File::SEPARATOR}#{pattern}"
          end

          pattern
        end
      end
    end
  end
end
