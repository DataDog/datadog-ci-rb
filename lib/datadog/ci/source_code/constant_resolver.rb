# frozen_string_literal: true

module Datadog
  module CI
    module SourceCode
      # ConstantResolver resolves Ruby constant names to their source file locations.
      #
      # This module uses Object.const_source_location to find where a constant is defined.
      # Constants defined in C extensions or built-in Ruby classes have no source location.
      #
      # This module mirrors the C implementation in datadog_common.c (dd_ci_resolve_const_to_file).
      module ConstantResolver
        # Resolve a constant name to its source file path.
        #
        # @param constant_name [String] The fully qualified constant name (e.g., "Foo::Bar::Baz")
        # @return [String, nil] The absolute file path where the constant is defined, or nil if not found
        def self.resolve(constant_name)
          return nil unless constant_name.is_a?(String)
          return nil if constant_name.empty?

          source_location = safely_get_const_source_location(constant_name)
          return nil unless source_location.is_a?(Array) && !source_location.empty?

          filename = source_location[0]
          return nil unless filename.is_a?(String)

          filename
        end

        # Safely get source location for a constant, returning nil on any exception.
        # This handles cases like anonymous classes, C-defined constants, etc.
        #
        # @param constant_name [String] The constant name to look up
        # @return [Array, nil] The [filename, lineno] array or nil
        def self.safely_get_const_source_location(constant_name)
          Object.const_source_location(constant_name)
        rescue
          nil
        end
      end
    end
  end
end
