# frozen_string_literal: true

require_relative "../../git/local_repository"
require_relative "../../file_serialization"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # Keeps native coverage, static dependencies, and custom impacted
        # files together and normalizes them as one set.
        #
        # @internal
        class Files
          EMPTY_FILES = [].freeze
          EMPTY_STATIC_DEPENDENCIES = [].freeze

          def initialize(
            coverage,
            custom_impacted_files = EMPTY_FILES,
            static_dependencies = EMPTY_STATIC_DEPENDENCIES
          )
            @coverage = coverage
            @custom_impacted_files = custom_impacted_files
            @static_dependencies = static_dependencies
            # The repository root is a process invariant between coverage
            # events, as is the repository-relative prefix of process-relative
            # paths. Capture both so asynchronous encoding uses the same exact
            # boundaries as the test thread without joining every filename.
            @root = Git::LocalRepository.root
            @relative_path_prefix = Git::LocalRepository.relative_path_prefix
            @normalized_files = nil
          end

          def each
            normalized_files.each { |file| yield file }
          end

          def size
            normalized_files.size
          end

          # Writes the complete MessagePack files array. The native fast path
          # combines absolute-path classification, immutable-root slicing,
          # stable deduplication, and filename-entry packing. Any shape it does
          # not support falls back before writing bytes.
          def write_to(packer)
            if FileSerialization.respond_to?(:pack_files) &&
                (packed_files = FileSerialization.pack_files(
                  @coverage,
                  @custom_impacted_files,
                  @root,
                  @static_dependencies,
                  @relative_path_prefix
                ))
              packer.buffer.write(packed_files)
              return packer
            end

            packer.write_array_header(size)
            each do |filename|
              packer.write_map_header(1)
              packer.write("filename")
              packer.write(filename)
            end
            packer
          end

          # Returns a readable view while preserving the paths supplied by
          # native coverage and the custom impacted-files API. Serialized files
          # are normalized through {#each}.
          def inspect_coverage
            coverage = @coverage.dup
            @static_dependencies.each do |dependencies|
              dependencies.each_key do |file|
                coverage[file] = true
              end
            end
            @custom_impacted_files.each do |file|
              coverage[file] = true
            end
            coverage
          end

          private

          def normalized_files
            @normalized_files ||= begin
              files = []
              @coverage.each_key do |file|
                relative_file = normalize(file)
                files << relative_file unless relative_file.empty?
              end
              @static_dependencies.each do |dependencies|
                dependencies.each_key do |file|
                  relative_file = normalize(file)
                  files << relative_file unless relative_file.empty?
                end
              end
              @custom_impacted_files.each do |file|
                relative_file = normalize(file)
                files << relative_file unless relative_file.empty?
              end
              files.uniq
            end
          end

          def normalize(file)
            return Git::LocalRepository.relative_to_root(file) if File.absolute_path?(file)

            file = file.delete_prefix("./")
            return file if @relative_path_prefix.empty?

            File.join(@relative_path_prefix, file)
          end
        end
      end
    end
  end
end
