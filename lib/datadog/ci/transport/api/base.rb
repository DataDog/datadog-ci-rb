# frozen_string_literal: true

require_relative "../../ext/transport"

module Datadog
  module CI
    module Transport
      module Api
        class Base
          def api_request(path:, payload:, headers: {}, verb: "post")
            headers[Ext::Transport::HEADER_CONTENT_TYPE] ||= Ext::Transport::CONTENT_TYPE_JSON
          end

          def citestcycle_request(path:, payload:, headers: {}, verb: "post")
            headers[Ext::Transport::HEADER_CONTENT_TYPE] ||= Ext::Transport::CONTENT_TYPE_MESSAGEPACK
          end

          def headers_with_default(headers)
            request_headers = default_headers
            request_headers.merge!(headers)
          end

          private

          def default_headers
            {}
          end
        end
      end
    end
  end
end
