# frozen_string_literal: true

require_relative "../../git/local_repository"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # Keeps native coverage and custom impacted files together and
        # normalizes them as one set.
        #
        # @internal
        class Files
          EMPTY_FILES = [].freeze

          def initialize(coverage, custom_impacted_files = EMPTY_FILES)
            @coverage = coverage
            @custom_impacted_files = custom_impacted_files
            @normalized_files = nil
          end

          def each
            normalized_files.each { |file| yield file }
          end

          def size
            normalized_files.size
          end

          # Returns a readable view while preserving the paths supplied by
          # native coverage and the custom impacted-files API. Serialized files
          # are normalized through {#each}.
          def inspect_coverage
            coverage = @coverage.dup
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
                relative_file = Git::LocalRepository.relative_to_root(file)
                files << relative_file unless relative_file.empty?
              end
              @custom_impacted_files.each do |file|
                # The public API defines relative custom paths as repository-relative.
                relative_file = if File.absolute_path?(file)
                  Git::LocalRepository.relative_to_root(file)
                else
                  file
                end
                files << relative_file unless relative_file.empty?
              end
              files.uniq
            end
          end
        end
      end
    end
  end
end
