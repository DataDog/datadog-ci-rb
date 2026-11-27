# frozen_string_literal: true

module Datadog
  module CI
    module Codeowners
      class Rule
        GLOB_CHARS = /[*?\[\\]/.freeze

        attr_reader :pattern, :owners

        def initialize(pattern, owners)
          @pattern = pattern
          @owners = owners
          @flags = compute_flags(pattern)
          @match_all = (pattern == "*")

          glob_index = pattern.index(GLOB_CHARS)
          if glob_index.nil?
            @directory_prefix = pattern.end_with?(::File::SEPARATOR) ? pattern : "#{pattern}#{::File::SEPARATOR}"
            @literal_prefix = nil
            @directory_pattern = nil
          else
            @directory_prefix = nil
            @literal_prefix = (glob_index > 0) ? pattern[0, glob_index] : nil
            @directory_pattern = if !pattern.end_with?(::File::SEPARATOR, "*")
              "#{pattern}#{::File::SEPARATOR}*"
            end
          end
        end

        def match?(file_path)
          return true if @match_all

          if (directory_prefix = @directory_prefix)
            return file_path == @pattern || file_path.start_with?(directory_prefix)
          end

          if (literal_prefix = @literal_prefix)
            return false unless file_path.start_with?(literal_prefix)
          end

          if (directory_pattern = @directory_pattern)
            return true if File.fnmatch?(directory_pattern, file_path, @flags)
          end

          File.fnmatch?(@pattern, file_path, @flags)
        end

        private

        def compute_flags(pattern)
          # prevents /path/* from matching subfolders
          return ::File::FNM_PATHNAME if pattern.end_with?("#{::File::SEPARATOR}*")
          # prevents /path/*.rb from matching Ruby files in subfolders
          return ::File::FNM_PATHNAME if pattern.include?("*.")
          # allows /path/**/subfolder to match both /path/subfolder and /path/a/b/c/subfolder
          return ::File::FNM_PATHNAME if pattern.include?("#{::File::SEPARATOR}**#{::File::SEPARATOR}")

          0
        end
      end
    end
  end
end
