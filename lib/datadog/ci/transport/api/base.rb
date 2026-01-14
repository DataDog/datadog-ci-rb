# frozen_string_literal: true

require "securerandom"

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
            citestcov_request_boundary = ::SecureRandom.uuid

            headers[Ext::Transport::HEADER_CONTENT_TYPE] ||=
              "#{Ext::Transport::CONTENT_TYPE_MULTIPART_FORM_DATA}; boundary=#{citestcov_request_boundary}"

            @citestcov_payload = [
              "--#{citestcov_request_boundary}",
              'Content-Disposition: form-data; name="event"; filename="event.json"',
              "Content-Type: application/json",
              "",
              '{"dummy":true}',
              "--#{citestcov_request_boundary}",
              'Content-Disposition: form-data; name="coverage1"; filename="coverage1.msgpack"',
              "Content-Type: application/msgpack",
              "",
              payload,
              "--#{citestcov_request_boundary}--"
            ].join("\r\n")
          end

          def logs_intake_request(path:, payload:, headers: {}, verb: "post")
            headers[Ext::Transport::HEADER_CONTENT_TYPE] ||= Ext::Transport::CONTENT_TYPE_JSON
          end

          def cicovreprt_request(path:, event_payload:, coverage_report_compressed:, headers: {}, verb: "post")
            cicovreprt_request_boundary = ::SecureRandom.uuid

            headers[Ext::Transport::HEADER_CONTENT_TYPE] ||=
              "#{Ext::Transport::CONTENT_TYPE_MULTIPART_FORM_DATA}; boundary=#{cicovreprt_request_boundary}"

            @cicovreprt_payload = [
              "--#{cicovreprt_request_boundary}",
              'Content-Disposition: form-data; name="event"; filename="event.json"',
              "Content-Type: application/json",
              "",
              event_payload,
              "--#{cicovreprt_request_boundary}",
              'Content-Disposition: form-data; name="coverage"; filename="coverage.gz"',
              "Content-Type: application/octet-stream",
              "",
              coverage_report_compressed,
              "--#{cicovreprt_request_boundary}--"
            ].join("\r\n")
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
