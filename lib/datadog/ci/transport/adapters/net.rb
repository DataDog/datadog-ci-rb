# frozen_string_literal: true

require "datadog/core/transport/response"
require "datadog/core/transport/ext"

require_relative "../gzip"
require_relative "../../ext/transport"

module Datadog
  module CI
    module Transport
      module Adapters
        # Adapter for Net::HTTP
        class Net
          attr_reader \
            :hostname,
            :port,
            :timeout,
            :ssl

          def initialize(hostname:, port:, ssl:, timeout_seconds:)
            @hostname = hostname
            @port = port
            @timeout = timeout_seconds
            @ssl = ssl
          end

          def open(&block)
            req = net_http_client.new(hostname, port)

            req.use_ssl = ssl
            req.open_timeout = req.read_timeout = timeout

            req.start(&block)
          end

          def call(path:, payload:, headers:, verb:)
            headers ||= {}
            # skip tracing for internal DD requests
            headers[Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST] = "1"

            if respond_to?(verb)
              send(verb, path: path, payload: payload, headers: headers)
            else
              raise "Unknown HTTP method [#{verb}]"
            end
          end

          def post(path:, payload:, headers:)
            post = ::Net::HTTP::Post.new(path, headers)
            post.body = payload

            # Connect and send the request
            http_response = open do |http|
              http.request(post)
            end

            # Build and return response
            Response.new(http_response)
          end

          class Response
            include Datadog::Core::Transport::Response

            attr_reader :http_response

            def initialize(http_response)
              @http_response = http_response
            end

            def payload
              return @decompressed_payload if defined?(@decompressed_payload)
              return http_response.body unless gzipped_content?
              return http_response.body unless gzipped_body?(http_response.body)

              Datadog.logger.debug("Decompressing gzipped response payload")
              @decompressed_payload = Gzip.decompress(http_response.body)
            end

            def header(name)
              http_response[name]
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

            def gzipped_content?
              header(Ext::Transport::HEADER_CONTENT_ENCODING) == Ext::Transport::CONTENT_ENCODING_GZIP
            end

            def gzipped_body?(body)
              return false if body.nil? || body.empty?

              # no-dd-sa
              first_bytes = body[0, 2]
              return false if first_bytes.nil? || first_bytes.empty?

              first_bytes.b == Ext::Transport::GZIP_MAGIC_NUMBER
            end

            def inspect
              "#{super}, http_response:#{http_response}"
            end
          end

          private

          def net_http_client
            return ::Net::HTTP unless defined?(WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP)

            WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP
          end
        end
      end
    end
  end
end
