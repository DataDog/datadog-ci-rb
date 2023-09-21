# frozen_string_literal: true

require "net/http"

module Datadog
  module CI
    module Transport
      class HTTP
        attr_reader \
          :host,
          :port,
          :ssl,
          :timeout

        DEFAULT_TIMEOUT = 30

        def initialize(host:, timeout: DEFAULT_TIMEOUT, port: nil, ssl: true)
          @host = host
          @port = port
          @timeout = timeout
          @ssl = ssl.nil? ? true : ssl
        end

        def request(path:, payload:, headers:, method: "post")
          raise "Unknown method #{method}" unless respond_to?(method, true)

          send(method, path: path, payload: payload, headers: headers)
        end

        private

        def open(&block)
          req = ::Net::HTTP.new(@host, @port)

          req.use_ssl = @ssl
          req.open_timeout = req.read_timeout = @timeout

          req.start(&block)
        end

        def post(path:, headers:, payload:)
          post = ::Net::HTTP::Post.new(path, headers)
          post.body = payload

          http_response = open do |http|
            http.request(post)
          end

          Response.new(http_response)
        rescue => e
          Datadog.logger.debug("Unable to send events: #{e}")

          InternalErrorResponse.new(e)
        end

        # Data structure for an HTTP Response
        class Response
          attr_reader :http_response

          def initialize(http_response)
            @http_response = http_response
          end

          def payload
            http_response.body
          end

          def code
            http_response.code.to_i
          end

          def ok?
            code.between?(200, 299)
          end

          def unsupported?
            code == 415
          end

          def not_found?
            code == 404
          end

          def client_error?
            code.between?(400, 499)
          end

          def server_error?
            code.between?(500, 599)
          end

          def internal_error?
            false
          end

          def inspect
            "#{self.class} ok?:#{ok?} unsupported?:#{unsupported?}, " \
            "not_found?:#{not_found?}, client_error?:#{client_error?}, " \
            "server_error?:#{server_error?}, internal_error?:#{internal_error?}, " \
            "payload:#{payload}"
          end
        end

        class InternalErrorResponse < Response
          class DummyNetHTTPResponse
            def body
              ""
            end

            def code
              "-1"
            end
          end

          attr_reader :error

          def initialize(error)
            super(DummyNetHTTPResponse.new)

            @error = error
          end

          def internal_error?
            true
          end

          def inspect
            "#{super}, error_class:#{error.class}, error:#{error}"
          end
        end
      end
    end
  end
end
