# frozen_string_literal: true

require "net/http"
require "socket"
require "timeout"

module Datadog
  module CI
    module Transport
      module Adapters
        module NetHttpClient
          def self.original_net_http
            return ::Net::HTTP unless defined?(WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP)

            WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP
          end

          # A Net::HTTP connection to an agent on a Unix domain socket. Like the
          # TCP connections, it is built on original_net_http so that WebMock
          # leaves it alone; the host and port only go in the Host header.
          def self.unix_socket_net_http(uds_path)
            # @type var http: Net::HTTP & UnixSocketConnection
            http = _ = original_net_http.new("localhost", 80).extend(UnixSocketConnection)
            http.uds_path = uds_path
            http
          end

          # Connects a Net::HTTP to a Unix domain socket instead of a host and port.
          module UnixSocketConnection
            attr_accessor :uds_path

            private

            def connect
              unix_socket = ::Timeout.timeout(open_timeout, ::Net::OpenTimeout) { ::UNIXSocket.new(uds_path) }
              @socket = ::Net::BufferedIO.new(
                unix_socket,
                read_timeout: read_timeout,
                write_timeout: write_timeout,
                continue_timeout: continue_timeout
              )
            end
          end
        end
      end
    end
  end
end
