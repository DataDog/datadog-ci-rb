# frozen_string_literal: true

module FileAccessFixtures
  class DownloadFile < File
    attr_reader :path_queries

    def path
      @path_queries = (@path_queries || 0) + 1
      "download://#{super}"
    end
  end

  class TrackedPath < String
    attr_reader :metadata_queries

    def encoding
      @metadata_queries = (@metadata_queries || 0) + 1
      super
    end

    def dup
      @metadata_queries = (@metadata_queries || 0) + 1
      super
    end

    def initialize_dup(other)
      raise "Customer path duplication"
    end
  end
end
