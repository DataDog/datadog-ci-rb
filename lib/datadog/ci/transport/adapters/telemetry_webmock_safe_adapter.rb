# frozen_string_literal: true

require_relative "net_http_client"

module Datadog
  module CI
    module Transport
      module Adapters
        module TelemetryWebmockSafeAdapter
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def open(&block)
              req = NetHttpClient.original_net_http.new(@hostname, @port)

              req.use_ssl = @ssl
              req.open_timeout = req.read_timeout = @timeout

              req.start(&block)
            end
          end
        end
      end
    end
  end
end
