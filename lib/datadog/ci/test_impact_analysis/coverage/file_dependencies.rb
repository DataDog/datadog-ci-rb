# frozen_string_literal: true

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # Resolves dependency names and applies the same boundaries to aliases
        # and their targets. It owns no per-test state or instrumentation.
        class FileDependencies
          def initialize(root:, ignored_path:)
            @root = File.join(root, "")
            @ignored_path = File.join(ignored_path, "") if ignored_path
          end

          def paths_for(file)
            path = file.is_a?(File) ? file.path : file
            return [] unless path

            if respond_to?(:native_paths, true)
              paths = native_paths(path, @root, @ignored_path)
              return paths if paths
            end

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
