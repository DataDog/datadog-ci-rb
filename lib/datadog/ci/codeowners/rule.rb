module Datadog
  module CI
    module Codeowners
      class Rule
        attr_reader :pattern, :owners

        def initialize(pattern, owners)
          @pattern = pattern
          @owners = owners
        end

        def match?(file_path)
          res = false
          # if pattern does not end with a separator or a wildcard, it could be either a directory or a file
          if !pattern.end_with?(::File::SEPARATOR, "*")
            directory_pattern = "#{pattern}#{::File::SEPARATOR}*"
            res ||= File.fnmatch?(directory_pattern, file_path, flags)
          end

          res ||= File.fnmatch?(pattern, file_path, flags)
          res
        end

        private

        def flags
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
