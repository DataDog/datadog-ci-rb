# frozen_string_literal: true

require "zlib"
require "stringio"

module Datadog
  module CI
    module Transport
      module Gzip
        module_function

        def compress(input)
          gzip_writer = Zlib::GzipWriter.new(StringIO.new)
          gzip_writer << input
          gzip_writer.close.string
        end
      end
    end
  end
end
