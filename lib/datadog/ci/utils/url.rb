# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module Url
        def self.filter_sensitive_info(url)
          return nil if url.nil?

          url.gsub(%r{((https?|ssh)://)[^/]*@}, '\1')
        end
      end
    end
  end
end
