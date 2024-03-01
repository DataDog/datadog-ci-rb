# frozen_string_literal: true

require_relative "../../ext/transport"

module Datadog
  module CI
    module Transport
      module Api
        class Base
          attr_reader :http

          def initialize(http:)
            @http = http
          end

          def request(path:, payload:, headers: {}, verb: "post")
            request_headers = default_headers
            request_headers.merge!(headers)

            http.request(
              path: path,
              payload: payload,
              verb: verb,
              headers: request_headers
            )
          end

          private

          def default_headers
            {
              Ext::Transport::HEADER_CONTENT_TYPE => Ext::Transport::CONTENT_TYPE_MESSAGEPACK
            }
          end
        end
      end
    end
  end
end
