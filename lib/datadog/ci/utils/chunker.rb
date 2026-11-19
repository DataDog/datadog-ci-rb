# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module Chunker
        def self.chunk_by_size(items, maximum)
          chunks = []
          current = []
          bytes = 0
          items.each do |item|
            if bytes + item.bytesize > maximum && !current.empty?
              chunks << current
              current = []
              bytes = 0
            end
            current << item
            bytes += item.bytesize
          end
          chunks << current unless current.empty?
          chunks
        end
      end
    end
  end
end
