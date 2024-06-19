# frozen_string_literal: true

require_relative "base"
require_relative "../../ext/transport"

module Datadog
  module CI
    module Transport
      module Api
        class Agentless < Base
          attr_reader :api_key

          def initialize(api_key:, citestcycle_url:, api_url:, citestcov_url:)
            @api_key = api_key
            @citestcycle_http = build_http_client(citestcycle_url, compress: true)
            @api_http = build_http_client(api_url, compress: false)
            @citestcov_http = build_http_client(citestcov_url, compress: true)
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

          private

          def perform_request(http_client, path:, payload:, headers:, verb:, accept_compressed_response: false)
            http_client.request(
              path: path,
              payload: payload,
              headers: headers_with_default(headers),
              verb: verb,
              accept_compressed_response: accept_compressed_response
            )
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
