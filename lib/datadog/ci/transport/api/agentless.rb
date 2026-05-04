# frozen_string_literal: true

require_relative "base"
require_relative "../../ext/transport"

module Datadog
  module CI
    module Transport
      module Api
        class Agentless < Base
          attr_reader :api_key

          # HTTP status codes returned by the Datadog backend when a request is
          # rejected for authentication/authorization reasons (typically because
          # of a missing or invalid DD_API_KEY).
          AUTHENTICATION_ERROR_CODES = [401, 403].freeze

          # Substring we look for in the response payload to confirm the
          # rejection is API-key related rather than some other permission
          # issue. Examples of payloads we want to match:
          #   {"errors":[{"status":"403","title":"Forbidden","detail":"API key is missing"}]}
          #   {"errors":[{"status":"403","title":"Forbidden","detail":"API key is invalid"}]}
          API_KEY_ERROR_PAYLOAD_MARKER = "API key"

          def initialize(api_key:, citestcycle_url:, api_url:, citestcov_url:, logs_intake_url:, cicovreprt_url:)
            @api_key = api_key
            @citestcycle_http = build_http_client(citestcycle_url, compress: true)
            @api_http = build_http_client(api_url, compress: false)
            @citestcov_http = build_http_client(citestcov_url, compress: true)
            @logs_intake_http = build_http_client(logs_intake_url, compress: true)
            @cicovreprt_http = build_http_client(cicovreprt_url, compress: false)
            @api_key_error_logged = false
          end

          def citestcycle_request(path:, payload:, headers: {}, verb: "post")
            super

            perform_request(@citestcycle_http, path: path, payload: payload, headers: headers, verb: verb)
          end

          def api_request(path:, payload:, headers: {}, verb: "post")
            super

            perform_request(
              @api_http,
              path: path,
              payload: payload,
              headers: headers,
              verb: verb,
              accept_compressed_response: true
            )
          end

          def citestcov_request(path:, payload:, headers: {}, verb: "post")
            super

            perform_request(@citestcov_http, path: path, payload: @citestcov_payload, headers: headers, verb: verb)
          end

          def logs_intake_request(path:, payload:, headers: {}, verb: "post")
            super

            perform_request(@logs_intake_http, path: path, payload: payload, headers: headers, verb: verb)
          end

          def cicovreprt_request(path:, event_payload:, compressed_coverage_report:, headers: {}, verb: "post")
            super

            perform_request(@cicovreprt_http, path: path, payload: @cicovreprt_payload, headers: headers, verb: verb)
          end

          private

          def perform_request(http_client, path:, payload:, headers:, verb:, accept_compressed_response: false)
            response = http_client.request(
              path: path,
              payload: payload,
              headers: headers_with_default(headers),
              verb: verb,
              accept_compressed_response: accept_compressed_response
            )

            log_api_key_error(response)

            response
          end

          def log_api_key_error(response)
            return if @api_key_error_logged
            return unless AUTHENTICATION_ERROR_CODES.include?(response.code)
            return unless response.payload.to_s.include?(API_KEY_ERROR_PAYLOAD_MARKER)

            @api_key_error_logged = true

            if api_key.nil? || api_key.strip.empty?
              Datadog.logger.error do
                "DATADOG CONFIGURATION - TEST OPTIMIZATION - ATTENTION - " \
                "Datadog API rejected the request because DD_API_KEY is not set. " \
                "Please set DD_API_KEY environment variable to a valid Datadog API key. " \
                "Server response: #{response.payload}"
              end
            else
              Datadog.logger.error do
                "DATADOG CONFIGURATION - TEST OPTIMIZATION - ATTENTION - " \
                "Datadog API rejected the request because the configured DD_API_KEY is invalid. " \
                "Please verify that DD_API_KEY environment variable is set to a valid Datadog API key " \
                "for the configured DD_SITE. " \
                "Server response: #{response.payload}"
              end
            end
          end

          def build_http_client(url, compress:)
            uri = URI.parse(url)
            raise "Invalid agentless mode URL: #{url}" if uri.host.nil?

            Datadog::CI::Transport::HTTP.new(
              host: uri.host,
              port: uri.port || 80,
              ssl: uri.scheme == "https" || uri.port == 443,
              compress: compress
            )
          end

          def default_headers
            headers = super
            headers[Ext::Transport::HEADER_DD_API_KEY] = api_key
            headers
          end
        end
      end
    end
  end
end
