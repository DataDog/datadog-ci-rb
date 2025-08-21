# frozen_string_literal: true

require "delegate"
require "socket"

require "datadog/core/utils/time"

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
        MAX_BACKOFF = 30
        MAX_RETRY_TIME = 50

        # Errors that should not be retried - fail fast
        NON_RETRIABLE_ERRORS = [
          Timeout::Error,      # Don't slow down customers with timeouts
          Errno::EINVAL,       # Invalid argument
          Net::HTTPBadResponse # Malformed response - likely persistent issue
        ].freeze

        # Errors that can be retried - transient network issues
        RETRIABLE_ERRORS = [
          Errno::ECONNRESET, # Connection reset by peer
          EOFError,          # Unexpected connection close
          SocketError        # DNS/network issues
        ].freeze

        def initialize(host:, port:, timeout: DEFAULT_TIMEOUT, ssl: true, compress: false)
          @host = host
          @port = port
          @timeout = timeout
          @ssl = ssl.nil? || ssl
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
          response = nil

          duration_ms = Core::Utils::Time.measure(:float_millisecond) do
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

            response = perform_http_call(path: path, payload: payload, headers: headers, verb: verb, retries: retries, backoff: backoff)

            Datadog.logger.debug do
              "Received server response: #{response.inspect}"
            end
          end
          # @type var response: Datadog::CI::Transport::Adapters::Net::Response
          # @type var duration_ms: Float

          # set some stats about the request
          response.request_compressed = compress
          response.request_size = payload.bytesize
          response.duration_ms = duration_ms

          response
        end

        private

        def perform_http_call(path:, payload:, headers:, verb:, retries: MAX_RETRIES, backoff: INITIAL_BACKOFF, retry_start_time: Core::Utils::Time.get_time)
          response = nil

          begin
            response = adapter.call(
              path: path, payload: payload, headers: headers, verb: verb
            )
            return response if response.ok?

            if response.code == 429
              backoff = (response.header(Ext::Transport::HEADER_RATELIMIT_RESET) || 1).to_i

              Datadog.logger.debug do
                "Received rate limit response, retrying in #{backoff} seconds from X-RateLimit-Reset header"
              end
            elsif response.server_error?
              Datadog.logger.debug { "Received server error response, retrying in #{backoff} seconds" }
            else
              return response
            end
          rescue *NON_RETRIABLE_ERRORS => e
            Datadog.logger.debug { "Failed to send request with non-retriable error #{e} (#{e.message})" }
            return ErrorResponse.new(e)
          rescue *RETRIABLE_ERRORS => e
            Datadog.logger.debug { "Failed to send request with retriable error #{e} (#{e.message})" }
            response = ErrorResponse.new(e)
          end

          # Check if we've exceeded the maximum retry time
          elapsed_time_seconds = Core::Utils::Time.get_time - retry_start_time
          if elapsed_time_seconds >= MAX_RETRY_TIME
            Datadog.logger.error(
              "Failed to send request after #{elapsed_time_seconds.round(2)} seconds (exceeded MAX_RETRY_TIME of #{MAX_RETRY_TIME}s)"
            )
            return response
          end

          if retries.positive? && backoff <= MAX_BACKOFF
            sleep(backoff)

            perform_http_call(
              path: path,
              payload: payload,
              headers: headers,
              verb: verb,
              retries: retries - 1,
              backoff: backoff * 2,
              retry_start_time: retry_start_time
            )
          else
            Datadog.logger.error(
              "Failed to send request after #{MAX_RETRIES - retries} retries (current backoff value #{backoff})"
            )

            response
          end
        end

        def adapter
          @adapter ||= Datadog::CI::Transport::Adapters::Net.new(
            hostname: host, port: port, ssl: ssl, timeout_seconds: timeout
          )
        end

        class ErrorResponse < Adapters::Net::Response
          def initialize(error)
            @error = error
          end

          attr_reader :error

          def payload
            ""
          end

          def header(name)
            nil
          end

          def code
            nil
          end

          def response_size
            0
          end

          def inspect
            "ErrorResponse error:#{error}"
          end
        end
      end
    end
  end
end
