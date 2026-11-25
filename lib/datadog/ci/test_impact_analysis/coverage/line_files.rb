# frozen_string_literal: true

require_relative "../../git/local_repository"
require_relative "files"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # The files of a line coverage record: a line bitmap for each file with executed
        # lines, and the custom impacted files, which have no lines.
        #
        # A bitmap sets bit (line & 7) of byte (line >> 3) for each executed line.
        #
        # @internal
        class LineFiles
          # @param bitmaps [Hash<String, String>] binary bitmaps by repository-relative path
          # @param custom_impacted_files [Array<String>] absolute or repository-relative paths
          def initialize(bitmaps, custom_impacted_files = Files::EMPTY_FILES)
            @bitmaps = bitmaps
            @custom_impacted_files = custom_impacted_files.filter_map do |file|
              relative_file = File.absolute_path?(file) ? Git::LocalRepository.relative_to_root(file) : file
              relative_file unless relative_file.empty? || bitmaps.key?(relative_file)
            end
          end

          def each
            @bitmaps.each_key { |file| yield file }
            @custom_impacted_files.each { |file| yield file }
          end

          def size
            @bitmaps.size + @custom_impacted_files.size
          end

          def write_to(packer)
            packer.write_array_header(size)
            @bitmaps.each do |file, bitmap|
              packer.write_map_header(2)
              packer.write("filename")
              packer.write(file)
              packer.write("bitmap")
              packer.write(bitmap)
            end
            @custom_impacted_files.each do |file|
              packer.write_map_header(1)
              packer.write("filename")
              packer.write(file)
            end
            packer
          end

          # Executed line numbers by file; true for a file without lines.
          def inspect_coverage
            coverage = {}
            @bitmaps.each { |file, bitmap| coverage[file] = self.class.lines(bitmap) }
            @custom_impacted_files.each { |file| coverage[file] = true }
            coverage
          end

          def self.lines(bitmap)
            lines = []
            bitmap.each_byte.with_index do |byte, index|
              next if byte.zero?

              8.times { |bit| lines << (index * 8 + bit) if byte[bit] == 1 }
            end
            lines
          end
        end
      end
    end
  end
end
