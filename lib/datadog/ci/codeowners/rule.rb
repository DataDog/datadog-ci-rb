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
          if !pattern.end_with?(::File::SEPARATOR, "*") && !pattern.include?(".")
            # could be a directory
            directory_pattern = pattern + "#{::File::SEPARATOR}*"
            res ||= File.fnmatch?(directory_pattern, file_path, flags)
          end

          res ||= File.fnmatch?(pattern, file_path, flags)
          res
        end

        private

        def flags
          return ::File::FNM_PATHNAME if pattern.end_with?("#{::File::SEPARATOR}*")
          0
        end
      end
    end
  end
end
