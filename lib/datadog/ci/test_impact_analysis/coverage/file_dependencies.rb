# frozen_string_literal: true

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # Resolves dependency names and applies the same boundaries to aliases
        # and their targets. It owns no per-test state or instrumentation.
        class FileDependencies
          EMPTY_PATHS = [].freeze
          private_constant :EMPTY_PATHS

          def initialize(root:, ignored_path:)
            @root = File.join(root, "")
            @ignored_path = File.join(ignored_path, "") if ignored_path
            @native_paths_available = respond_to?(:native_paths, true)
          end

          def paths_for(file)
            path = case file
            when String then file
            when File then native_file_path(file)
            end
            return EMPTY_PATHS unless path

            if @native_paths_available
              paths = native_paths(path, @root, @ignored_path)
              return paths if paths
            end

            # Use a plain String so resolution cannot call customer overrides.
            path = String.new(path)
            path.force_encoding("filesystem") if path.encoding == Encoding::BINARY

            paths = [File.absolute_path(path)]
            resolved = resolve_target(path)
            paths << resolved if resolved && resolved != paths.first
            paths.select { |dependency| included?(dependency) }
          end

          private

          def resolve_target(path)
            # Resolve before collapsing .. across directory symlinks.
            File.realpath(path)
          rescue SystemCallError
            # Keep the opened name for missing targets and filesystem races.
            nil
          end

          def included?(path)
            ignored_path = @ignored_path
            path.start_with?(@root) && !(ignored_path && path.start_with?(ignored_path))
          end
        end
      end
    end
  end
end
