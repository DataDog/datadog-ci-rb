# frozen_string_literal: true

module Datadog
  module CI
    module SourceCode
      # PathFilter determines whether a file path should be included in test impact analysis.
      #
      # A path is included if:
      # - It starts with root_path (prefix match)
      # - It does NOT start with ignored_path (when ignored_path is set)
      #
      # This module mirrors the C implementation in datadog_common.c (dd_ci_is_path_included).
      module PathFilter
        # Check if a file path should be included in analysis.
        #
        # @param path [String] The file path to check
        # @param root_path [String] The root path prefix (required)
        # @param ignored_path [String, nil] Path prefix to exclude (optional)
        # @return [Boolean] true if the path should be included
        def self.included?(path, root_path, ignored_path = nil)
          return false unless path.is_a?(String) && root_path.is_a?(String)
          return false unless path.start_with?(root_path)

          if ignored_path.is_a?(String) && !ignored_path.empty?
            return false if path.start_with?(ignored_path)
          end

          true
        end
      end
    end
  end
end
