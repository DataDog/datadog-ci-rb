# frozen_string_literal: true

module Datadog
  module CI
    module Transport
      module Adapters
        module NetHttpClient
          def self.original_net_http
            return ::Net::HTTP unless defined?(WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP)

            WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP
          end
        end
      end
    end
  end
end
