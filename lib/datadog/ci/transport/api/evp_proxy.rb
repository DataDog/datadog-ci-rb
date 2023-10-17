# frozen_string_literal: true

require_relative "base"
require_relative "../http"

module Datadog
  module CI
    module Transport
      module Api
        class EVPProxy < Base
          attr_reader :http

          def initialize(url:)
            uri = URI.parse(url)
            raise "Invalid evp proxy mode URL: #{url}" if uri.host.nil?

            @http = Datadog::CI::Transport::HTTP.new(
              host: uri.host,
              port: uri.port,
              ssl: uri.scheme == "https" || uri.port == 443,
              compress: false
            )
          end

          def request(path:, payload:, verb: "post")
            path = "#{Ext::Transport::EVP_PROXY_PATH_PREFIX}#{path}"

            http.request(
              path: path,
              payload: payload,
              verb: verb,
              headers: headers
            )
          end

          private

          def container_id
            return @container_id if defined?(@container_id)

            @container_id = Datadog::Core::Environment::Container.container_id
          end

          def headers
            headers = super
            headers[Ext::Transport::HEADER_EVP_SUBDOMAIN] = Ext::Transport::TEST_VISIBILITY_INTAKE_HOST_PREFIX

            c_id = container_id
            headers[Ext::Transport::HEADER_CONTAINER_ID] = c_id unless c_id.nil?

            headers
          end
        end
      end
    end
  end
end
