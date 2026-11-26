# frozen_string_literal: true

require "msgpack"

require_relative "../../git/local_repository"
require_relative "files"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # The files of a line coverage record: a line bitmap for each file with executed
        # lines, and the custom impacted files, which have no lines.
        #
        # A bitmap sets bit (line & 7) of byte (line >> 3) for each executed line. The
        # bitmaps stay packed as they are sent: one msgpack map {"filename", "bitmap"} for
        # each file, back to back.
        #
        # @internal
        class LineFiles
          FILENAME = "filename"
          BITMAP = "bitmap"

          # @param bitmaps [Hash<String, String>] binary bitmaps by repository-relative path
          # @param custom_impacted_files [Array<String>] absolute or repository-relative paths
          def self.from_bitmaps(bitmaps, custom_impacted_files = Files::EMPTY_FILES)
            packer = MessagePack::Packer.new
            bitmaps.each do |file, bitmap|
              packer.write_map_header(2)
              packer.write(FILENAME)
              packer.write(file)
              packer.write(BITMAP)
              packer.write(bitmap)
            end
            new(bitmaps.size, packer.to_s, custom_impacted_files)
          end

          # @param bitmap_count [Integer] the number of maps in packed_bitmaps
          # @param packed_bitmaps [String] msgpack maps {"filename", "bitmap"}, back to back
          # @param custom_impacted_files [Array<String>] absolute or repository-relative paths
          def initialize(bitmap_count, packed_bitmaps, custom_impacted_files = Files::EMPTY_FILES)
            @bitmap_count = bitmap_count
            @packed_bitmaps = packed_bitmaps
            @custom_impacted_files = Files::EMPTY_FILES
            return if custom_impacted_files.empty?

            files_with_lines = bitmaps
            @custom_impacted_files = custom_impacted_files.filter_map do |file|
              absolute = Git::LocalRepository::REAL_FILE.absolute_path?(file)
              relative_file = absolute ? Git::LocalRepository.relative_to_root(file) : file
              relative_file unless relative_file.empty? || files_with_lines.key?(relative_file)
            end
          end

          def each
            bitmaps.each_key { |file| yield file }
            @custom_impacted_files.each { |file| yield file }
          end

          def size
            @bitmap_count + @custom_impacted_files.size
          end

          def write_to(packer)
            packer.write_array_header(size)
            packer.buffer << @packed_bitmaps
            @custom_impacted_files.each do |file|
              packer.write_map_header(1)
              packer.write(FILENAME)
              packer.write(file)
            end
            packer
          end

          # Executed line numbers by file; true for a file without lines.
          def inspect_coverage
            coverage = {}
            bitmaps.each { |file, bitmap| coverage[file] = self.class.lines(bitmap) }
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

          private

          # Binary bitmaps by repository-relative path, unpacked.
          def bitmaps
            unpacked = {}
            MessagePack::Unpacker.new.feed_each(@packed_bitmaps) do |map|
              unpacked[map.fetch(FILENAME)] = map.fetch(BITMAP)
            end
            unpacked
          end
        end
      end
    end
  end
end
