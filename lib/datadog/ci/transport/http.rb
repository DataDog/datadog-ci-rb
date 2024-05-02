# frozen_string_literal: true

require "delegate"
require "datadog/core/transport/http/adapters/net"
require "datadog/core/transport/http/env"
require "datadog/core/transport/request"
require "socket"

require_relative "gzip"
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

        def initialize(host:, timeout: DEFAULT_TIMEOUT, port: nil, ssl: true, compress: false)
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
            build_env(path: path, payload: payload, headers: headers, verb: verb)
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

        def build_env(path:, payload:, headers:, verb:)
          env = Datadog::Core::Transport::HTTP::Env.new(
            Datadog::Core::Transport::Request.new
          )
          env.body = payload
          env.path = path
          env.headers = headers
          env.verb = verb
          env
        end

        def adapter
          settings = AdapterSettings.new(hostname: host, port: port, ssl: ssl, timeout_seconds: timeout)
          @adapter ||= Datadog::Core::Transport::HTTP::Adapters::Net.new(settings)
        end

        # adds compatibility with Datadog::Tracing transport and
        class ResponseDecorator < ::SimpleDelegator
          def payload
            return @decompressed_payload if defined?(@decompressed_payload)

            if gzipped?(__getobj__.payload)
              @decompressed_payload = Gzip.decompress(__getobj__.payload)
            else
              __getobj__.payload
            end
          end

          def trace_count
            0
          end

          def gzipped?(payload)
            return false if payload.nil? || payload.empty?

            payload[0, 2] == "\x1F\x8B"
          end
        end

        class AdapterSettings
          attr_reader :hostname, :port, :ssl, :timeout_seconds

          def initialize(hostname:, port: nil, ssl: true, timeout_seconds: nil)
            @hostname = hostname
            @port = port
            @ssl = ssl
            @timeout_seconds = timeout_seconds
          end

          def ==(other)
            hostname == other.hostname && port == other.port && ssl == other.ssl &&
              timeout_seconds == other.timeout_seconds
          end
        end
      end
    end
  end
end
