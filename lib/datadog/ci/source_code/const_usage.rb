# frozen_string_literal: true

module Datadog
  module CI
    module SourceCode
      module ConstUsage
        begin
          require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

          CONST_MAP_AVAILABLE = true
        rescue LoadError
          CONST_MAP_AVAILABLE = false
        end

        def self.constants_used_in_file(file)
          return nil unless CONST_MAP_AVAILABLE
          return nil if file.nil?

          @file_to_const_map.fetch(file, [])
        end

        def self.usage_map
          @file_to_const_map
        end
      end
    end
  end
end
