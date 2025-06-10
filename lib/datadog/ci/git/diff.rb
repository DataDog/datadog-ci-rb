# frozen_string_literal: true

require "set"

module Datadog
  module CI
    module Git
      class Diff
        def initialize(changed_files: Set.new)
          @changed_files = changed_files
        end

        def include?(file_path)
          @changed_files.include?(file_path)
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

        def to_set
          @changed_files.dup
        end

        def self.parse_diff_output(output)
          return new if output.nil? || output.empty?

          changed_files = Set.new
          output.each_line do |line|
            # Match lines like: diff --git a/foo/bar.rb b/foo/bar.rb
            # This captures git changes on file level
            match = /^diff --git a\/(?<file>.+?) b\//.match(line)
            if match && match[:file]
              changed_file = match[:file]
              # Normalize to repo root
              normalized_changed_file = LocalRepository.relative_to_root(changed_file)
              changed_files << normalized_changed_file unless normalized_changed_file.nil? || normalized_changed_file.empty?

              Datadog.logger.debug { "matched changed_file: #{changed_file} from line: #{line}" }
              Datadog.logger.debug { "normalized_changed_file: #{normalized_changed_file}" }
            end
          end

          new(changed_files: changed_files)
        end
      end
    end
  end
end
