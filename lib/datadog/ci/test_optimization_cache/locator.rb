# frozen_string_literal: true

require_relative "../ext/test_optimization_cache"

module Datadog
  module CI
    module TestOptimizationCache
      class Locator
        RUNFILES_MANIFEST_SEPARATOR = " "

        def initialize(manifest_file:, runfiles_dir:, runfiles_manifest_file:, test_srcdir:)
          @manifest_file = manifest_file
          @runfiles_dir = runfiles_dir
          @runfiles_manifest_file = runfiles_manifest_file
          @test_srcdir = test_srcdir
          @manifest_versions = {}
        end

        def manifest_path
          return @manifest_path if defined?(@manifest_path)

          local_manifest = File.join(Ext::TestOptimizationCache::PLAN_FOLDER, Ext::TestOptimizationCache::MANIFEST_FILE_NAME)
          if File.exist?(local_manifest)
            @manifest_path = local_manifest
            return @manifest_path
          end

          manifest_file = @manifest_file
          if manifest_file && !manifest_file.empty?
            env_path = resolve_bazel_runfile_path(manifest_file)
            if File.exist?(env_path)
              @manifest_path = env_path
              return @manifest_path
            end
          end

          @manifest_path = nil
        end

        def manifest_version(manifest_path)
          return @manifest_versions[manifest_path] if @manifest_versions.key?(manifest_path)

          @manifest_versions[manifest_path] = File.read(manifest_path).delete_prefix("\uFEFF").strip
        rescue => e
          Datadog.logger.debug { "Failed to read Test Optimization cache manifest #{manifest_path}: #{e.message}" }
          @manifest_versions[manifest_path] = nil
        end

        def resolve_bazel_runfile_path(path)
          return path if File.exist?(path)

          runfiles_dir = @runfiles_dir
          if runfiles_dir && !runfiles_dir.empty?
            candidate = File.join(runfiles_dir, path)
            return candidate if File.exist?(candidate)
          end

          manifest_candidate = resolve_bazel_runfile_path_from_manifest(path)
          return manifest_candidate if manifest_candidate

          test_srcdir = @test_srcdir
          if test_srcdir && !test_srcdir.empty?
            candidate = File.join(test_srcdir, path)
            return candidate if File.exist?(candidate)
          end

          path
        end

        # Bazel can provide runfiles through a manifest file instead of a directory tree.
        # Each line maps a logical runfile path to the actual path on disk.
        def resolve_bazel_runfile_path_from_manifest(path)
          runfiles_manifest = @runfiles_manifest_file
          return nil if runfiles_manifest.nil? || runfiles_manifest.empty?
          return nil unless File.exist?(runfiles_manifest)

          File.foreach(runfiles_manifest) do |line|
            separator_index = line.index(RUNFILES_MANIFEST_SEPARATOR)
            next unless separator_index&.positive?
            next unless line[0...separator_index] == path

            resolved_path = line[(separator_index + 1)..]
            return resolved_path.strip if resolved_path
          end

          nil
        rescue => e
          Datadog.logger.debug do
            "Failed to resolve Test Optimization cache manifest from #{runfiles_manifest}: #{e.message}"
          end
          nil
        end
      end
    end
  end
end
