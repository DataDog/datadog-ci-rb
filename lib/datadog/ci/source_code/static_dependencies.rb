# frozen_string_literal: true

module Datadog
  module CI
    module SourceCode
      module StaticDependencies
        STATIC_DEPENDENCIES_AVAILABLE = begin
          if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.2")
            require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
            true
          else
            false
          end
        rescue LoadError
          false
        end

        def self.fetch_static_dependencies(file)
          return {} unless STATIC_DEPENDENCIES_AVAILABLE
          return {} unless @dependencies_map
          return {} if file.nil?

          @dependencies_map.fetch(file, {})
        end
      end
    end
  end
end
