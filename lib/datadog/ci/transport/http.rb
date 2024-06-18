# frozen_string_literal: true

require "delegate"
require "socket"

require_relative "gzip"
require_relative "adapters/net"
require_relative "../ext/transport"

module Datadog
  module CI
    module Transport
      class HTTP
        attr_reader \
          :host,
          :port,
          :ssl,
          :timeout,
          :compress

        DEFAULT_TIMEOUT = 30
        MAX_RETRIES = 3
        INITIAL_BACKOFF = 1

        def initialize(host:, port:, timeout: DEFAULT_TIMEOUT, ssl: true, compress: false)
          @host = host
          @port = port
          @timeout = timeout
          @ssl = ssl.nil? ? true : ssl
          @compress = compress.nil? ? false : compress
        end

        def request(
          path:,
          payload:,
          headers:,
          verb: "post",
          retries: MAX_RETRIES,
          backoff: INITIAL_BACKOFF,
          accept_compressed_response: false
        )
          if compress
            headers[Ext::Transport::HEADER_CONTENT_ENCODING] = Ext::Transport::CONTENT_ENCODING_GZIP
            payload = Gzip.compress(payload)
          end

          if accept_compressed_response
            headers[Ext::Transport::HEADER_ACCEPT_ENCODING] = Ext::Transport::CONTENT_ENCODING_GZIP
          end

          Datadog.logger.debug do
            "Sending #{verb} request: host=#{host}; port=#{port}; ssl_enabled=#{ssl}; " \
              "compression_enabled=#{compress}; path=#{path}; payload_size=#{payload.size}"
          end

          response = ResponseDecorator.new(
            perform_http_call(path: path, payload: payload, headers: headers, verb: verb, retries: retries, backoff: backoff)
          )

          Datadog.logger.debug do
            "Received server response: #{response.inspect}"
          end

          response
        end

        private

        def perform_http_call(path:, payload:, headers:, verb:, retries: MAX_RETRIES, backoff: INITIAL_BACKOFF)
          adapter.call(
            path: path, payload: payload, headers: headers, verb: verb
          )
        rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError, SocketError, Net::HTTPBadResponse => e
          Datadog.logger.debug("Failed to send request with #{e} (#{e.message})")

          if retries.positive?
            sleep(backoff)

            perform_http_call(
              path: path, payload: payload, headers: headers, verb: verb, retries: retries - 1, backoff: backoff * 2
            )
          else
            Datadog.logger.error("Failed to send request after #{MAX_RETRIES} retries")
            raise e
          end
        end

        def adapter
          @adapter ||= Datadog::CI::Transport::Adapters::Net.new(
            hostname: host, port: port, ssl: ssl, timeout_seconds: timeout
          )
        end

        # adds compatibility with Datadog::Tracing transport and
        # provides ungzipping capabilities
        class ResponseDecorator < ::SimpleDelegator
          def trace_count
            0
          end
        end
      end
    end
  end
end
