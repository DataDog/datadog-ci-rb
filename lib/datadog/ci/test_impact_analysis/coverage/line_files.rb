# frozen_string_literal: true

require "msgpack"

require_relative "../../git/local_repository"
require_relative "files"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # The files of a line coverage record: a line bitmap for each file with executed
        # lines, and the files the test depends on without lines, such as the custom
        # impacted files and the files it opened.
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
          # @param files_without_lines [Array<String>] absolute or repository-relative paths
          def self.from_bitmaps(bitmaps, files_without_lines = Files::EMPTY_FILES)
            count, packed = pack(bitmaps)
            new(count, packed, files_without_lines)
          end

          # @param bitmaps [Hash<String, String>] binary bitmaps by repository-relative path
          # @return [Array(Integer, String)] the number of maps and the packed maps
          def self.pack(bitmaps)
            packer = MessagePack::Packer.new
            bitmaps.each do |file, bitmap|
              packer.write_map_header(2)
              packer.write(FILENAME)
              packer.write(file)
              packer.write(BITMAP)
              packer.write(bitmap)
            end
            [bitmaps.size, packer.to_s]
          end

          # @param packed_bitmaps [String] msgpack maps {"filename", "bitmap"}, back to back
          # @return [Hash<String, String>] binary bitmaps by repository-relative path
          def self.unpack(packed_bitmaps)
            unpacked = {}
            MessagePack::Unpacker.new.feed_each(packed_bitmaps) do |map|
              unpacked[map.fetch(FILENAME)] = map.fetch(BITMAP)
            end
            unpacked
          end

          # Adds the lines of more bitmaps to the bitmaps, by repository-relative path.
          def self.add_bitmaps(bitmaps, more)
            more.each { |file, bitmap| bitmaps[file] = union(bitmaps[file], bitmap) }
            bitmaps
          end

          def self.union(left, right)
            return right.b if left.nil?

            longer, shorter = (left.bytesize >= right.bytesize) ? [left, right] : [right, left]
            bytes = longer.bytes
            shorter.each_byte.with_index { |byte, index| bytes[index] |= byte }
            bytes.pack("C*")
          end

          # @param bitmap_count [Integer] the number of maps in packed_bitmaps
          # @param packed_bitmaps [String] msgpack maps {"filename", "bitmap"}, back to back
          # @param files_without_lines [Array<String>] absolute or repository-relative paths
          def initialize(bitmap_count, packed_bitmaps, files_without_lines = Files::EMPTY_FILES)
            @bitmap_count = bitmap_count
            @packed_bitmaps = packed_bitmaps
            @files_without_lines = Files::EMPTY_FILES
            return if files_without_lines.empty?

            files_with_lines = bitmaps
            relative_files = {}
            files_without_lines.each do |file|
              absolute = Git::LocalRepository::REAL_FILE.absolute_path?(file)
              relative_file = utf8_path(absolute ? Git::LocalRepository.relative_to_root(file) : file)
              relative_files[relative_file] = true unless relative_file.empty? || files_with_lines.key?(relative_file)
            end
            @files_without_lines = relative_files.keys
          end

          def each
            bitmaps.each_key { |file| yield file }
            @files_without_lines.each { |file| yield file }
          end

          def size
            @bitmap_count + @files_without_lines.size
          end

          def write_to(packer)
            packer.write_array_header(size)
            packer.buffer << @packed_bitmaps
            @files_without_lines.each do |file|
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
            @files_without_lines.each { |file| coverage[file] = true }
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
            self.class.unpack(@packed_bitmaps)
          end

          # msgpack packs a binary string as bin, not as a string. A path that the test passed
          # as a binary string is still a filename, so it goes as UTF-8 if its bytes are UTF-8.
          def utf8_path(path)
            return path unless path.encoding == Encoding::BINARY

            utf8 = path.dup.force_encoding(Encoding::UTF_8)
            utf8.valid_encoding? ? utf8 : path
          end
        end
      end
    end
  end
end
