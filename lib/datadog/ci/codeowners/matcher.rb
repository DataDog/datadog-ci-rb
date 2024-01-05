# frozen_string_literal: true

require_relative "rule"

module Datadog
  module CI
    module Codeowners
      # Responsible for matching a file path to a list of owners
      class Matcher
        def initialize(codeowners_file_path)
          @rules = parse(codeowners_file_path)
          @rules.reverse!
        end

        def list_owners(file_path)
          @rules.each do |rule|
            return rule.owners if rule.match?(file_path)
          end

          []
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
              next if pattern.nil? || pattern.empty? || line_owners.empty?

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
      end
    end
  end
end
