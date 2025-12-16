# frozen_string_literal: true

module Datadog
  module CI
    module SourceCode
      module StaticDependencies
        begin
          require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

          NATIVE_EXTENSION_AVAILABLE = true
        rescue LoadError
          NATIVE_EXTENSION_AVAILABLE = false
        end

        def self.fetch_static_dependencies(file)
          return {} unless NATIVE_EXTENSION_AVAILABLE
          return {} unless @dependencies_map
          return {} if file.nil?

          @dependencies_map.fetch(file, {})
        end
      end
    end
  end
end
