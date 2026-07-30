# frozen_string_literal: true

require_relative "../../git/local_repository"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # Keeps TIA file collections together and normalizes them as one set.
        #
        # Collections are retained separately until their normalized contents
        # are needed, avoiding an eager merge on the test execution path.
        #
        # @internal
        class Files
          EMPTY_FILES = [].freeze
          EMPTY_COLLECTIONS = [].freeze

          def initialize(*collections)
            collections.reject!(&:empty?)
            @collections = collections
            @normalized_files = nil
          end

          def add_collection(collection)
            return if collection.empty?

            @collections << collection
            @normalized_files = nil
          end

          def each
            normalized_files.each { |file| yield file }
          end

          def size
            normalized_files.size
          end

          # Returns a readable view while preserving the paths supplied by each
          # collector. Serialized files are normalized through {#each}.
          def inspect_coverage
            @collections.each_with_object({}) do |collection, coverage|
              if collection.is_a?(Hash)
                coverage.merge!(collection)
              else
                collection.each { |file| coverage[file] = true }
              end
            end
          end

          private

          def normalized_files
            @normalized_files ||= begin
              files = {}
              each_raw_file do |file|
                files[Git::LocalRepository.relative_to_root(file)] = true
              end
              files.keys
            end
          end

          def each_raw_file
            @collections.each do |collection|
              if collection.is_a?(Hash)
                collection.each_key { |file| yield file }
              else
                collection.each { |file| yield file }
              end
            end
          end
        end
      end
    end
  end
end
