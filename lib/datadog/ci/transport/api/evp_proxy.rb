# frozen_string_literal: true

require "datadog/core/environment/container"

require_relative "base"
require_relative "../../ext/transport"

module Datadog
  module CI
    module Transport
      module Api
        class EvpProxy < Base
          def initialize(http:, path_prefix: Ext::Transport::EVP_PROXY_V2_PATH_PREFIX)
            super(http: http)

            path_prefix = "#{path_prefix}/" unless path_prefix.end_with?("/")
            @path_prefix = path_prefix
          end

          def request(path:, payload:, headers: {}, verb: "post")
            path = "#{@path_prefix}#{path.sub(/^\//, "")}"

            super(
              path: path,
              payload: payload,
              headers: headers,
              verb: verb
            )
          end

          private

          def container_id
            return @container_id if defined?(@container_id)

            @container_id = Datadog::Core::Environment::Container.container_id
          end

          def default_headers
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
