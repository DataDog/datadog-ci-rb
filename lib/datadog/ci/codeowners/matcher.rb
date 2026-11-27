# frozen_string_literal: true

require_relative "rule"

module Datadog
  module CI
    module Codeowners
      # Responsible for matching a test source file path to a list of owners
      class Matcher
        CACHE_MISS = Object.new.freeze

        def initialize(codeowners_file_path)
          @rules = parse(codeowners_file_path)
          @rules.reverse!
          @cache = {}
          @mutex = Mutex.new
        end

        def list_owners(file_path)
          return nil if @rules.empty?

          cached = @mutex.synchronize { @cache.fetch(file_path, CACHE_MISS) }
          return cached if cached.is_a?(Array)
          return nil if cached.nil?

          # treat all file paths that we check as absolute from the repository root
          normalized_path = file_path.start_with?("/") ? file_path : "/#{file_path}"

          Datadog.logger.debug { "Matching file path #{normalized_path} to CODEOWNERS rules" }

          matched_owners = nil
          @rules.each do |rule|
            if rule.match?(normalized_path)
              Datadog.logger.debug { "Matched rule [#{rule.pattern}] with owners #{rule.owners}" }
              matched_owners = rule.owners
              break
            end
          end

          Datadog.logger.debug { "CODEOWNERS rule not matched" } if matched_owners.nil?

          @mutex.synchronize do
            @cache[file_path] = matched_owners
          end

          matched_owners
        end

        private

        def parse(codeowners_file_path)
          unless File.exist?(codeowners_file_path)
            Datadog.logger.debug { "CODEOWNERS file not found at #{codeowners_file_path}" }
            return []
          end

          result = []
          section_default_owners = []

          File.open(codeowners_file_path, "r") do |f|
            f.each_line do |line|
              line.strip!&.sub!(/#.*$/, "")

              next if line.empty?
              next if comment?(line)

              pattern, *line_owners = line.strip.split(/\s+/)
              next if pattern.nil? || pattern.empty?

              # if the current line starts with section record the default owners for this section
              if section?(pattern)
                section_default_owners = line_owners
                next
              end

              pattern = expand_pattern(pattern)
              # if the current line doesn't have any owners then use the default owners for this section
              if line_owners.empty? && !section_default_owners.empty?
                line_owners = section_default_owners
              end

              result << Rule.new(pattern, line_owners)
            end
          end

          result
        rescue => e
          Datadog.logger.warn(
            "Failed to parse codeowners file at #{codeowners_file_path}: " \
              "#{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
          )
          []
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
          pattern << "**" if pattern.end_with?(::File::SEPARATOR)

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
