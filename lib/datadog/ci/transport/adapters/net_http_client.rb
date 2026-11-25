# frozen_string_literal: true

require "net/http"
require "cgi/util"
require "socket"
require "timeout"

module Datadog
  module CI
    module Transport
      module Adapters
        module NetHttpClient
          GET_CONSTRUCTOR = ::Net::HTTP::Get.method(:new)
          POST_CONSTRUCTOR = ::Net::HTTP::Post.method(:new)
          private_constant :GET_CONSTRUCTOR, :POST_CONSTRUCTOR

          def self.get_request(path, headers)
            GET_CONSTRUCTOR.call(path, headers)
          end

          def self.post_request(path, headers)
            POST_CONSTRUCTOR.call(path, headers)
          end

          def self.original_net_http
            return ::Net::HTTP unless defined?(WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP)

            WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP
          end

          CONNECTION_CONSTRUCTOR = original_net_http.method(:new)
          private_constant :CONNECTION_CONSTRUCTOR

          def self.proxy_options(hostname, port)
            proxy = ::URI::HTTP.new("http", nil, hostname, port, nil, nil, nil, nil, nil).find_proxy
            user = proxy&.user
            password = proxy&.password
            [proxy&.hostname, proxy&.port, (CGI.unescape(user) if user), (CGI.unescape(password) if password)]
          end

          def self.net_http(hostname, port, proxy_options = nil)
            if proxy_options
              CONNECTION_CONSTRUCTOR.call(hostname, port, *proxy_options)
            else
              CONNECTION_CONSTRUCTOR.call(hostname, port)
            end
          end

          # A Net::HTTP connection to an agent on a Unix domain socket. Like the
          # TCP connections, it is built on original_net_http so that WebMock
          # leaves it alone; the host and port only go in the Host header.
          def self.unix_socket_net_http(uds_path)
            # @type var http: Net::HTTP & UnixSocketConnection
            http = _ = net_http("localhost", 80, [nil, nil, nil, nil]).extend(UnixSocketConnection)
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
