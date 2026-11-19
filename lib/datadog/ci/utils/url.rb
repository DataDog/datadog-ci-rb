# frozen_string_literal: true

require "uri"

module Datadog
  module CI
    module Utils
      module Url
        def self.filter_basic_auth(url)
          return nil if url.nil?

          URI(url).tap do |uri|
            uri.user = nil
            uri.password = nil
          end.to_s
        rescue URI::InvalidURIError
          url
        end
      end
    end
  end
end
