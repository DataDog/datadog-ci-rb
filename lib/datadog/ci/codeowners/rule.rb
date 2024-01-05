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
          File.fnmatch?(pattern, file_path)
        end
      end
    end
  end
end
