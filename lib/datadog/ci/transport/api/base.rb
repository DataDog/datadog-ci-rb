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

          def citestcov_request(path:, payload:, headers: {}, verb: "post")
            citestcov_request_boundary = "1"

            headers[Ext::Transport::HEADER_CONTENT_TYPE] ||=
              "#{Ext::Transport::CONTENT_TYPE_MULTIPART_FORM_DATA}; boundary=#{citestcov_request_boundary}"

            @citestcov_payload = <<~PAYLOAD
              --#{citestcov_request_boundary}
              Content-Disposition: form-data; name="event"; filename="event.json"
              Content-Type: application/json

              {"dummy":true}
              --#{citestcov_request_boundary}
              Content-Disposition: form-data; name="coverage1"; filename="coverage1.msgpack"
              Content-Type: application/msgpack

              #{payload}
              --#{citestcov_request_boundary}--
            PAYLOAD
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
