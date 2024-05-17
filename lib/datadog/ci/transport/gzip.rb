# frozen_string_literal: true

require "zlib"
require "stringio"

module Datadog
  module CI
    module Transport
      module Gzip
        module_function

        def compress(input)
          sio = StringIO.new
          gzip_writer = Zlib::GzipWriter.new(sio, Zlib::DEFAULT_COMPRESSION, Zlib::DEFAULT_STRATEGY)
          gzip_writer << input
          gzip_writer.close
          sio.string
        end

        def decompress(input)
          sio = StringIO.new(input)
          gzip_reader = Zlib::GzipReader.new(
            sio,
            external_encoding: Encoding::UTF_8,
            internal_encoding: Encoding::UTF_8
          )
          gzip_reader.read || ""
        ensure
          gzip_reader&.close
        end
      end
    end
  end
end
