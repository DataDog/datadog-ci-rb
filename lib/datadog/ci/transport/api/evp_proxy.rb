# frozen_string_literal: true

require "datadog/core/environment/container"

require_relative "base"
require_relative "../../ext/transport"

module Datadog
  module CI
    module Transport
      module Api
        class EvpProxy < Base
          def initialize(agent_settings:, path_prefix: Ext::Transport::EVP_PROXY_V2_PATH_PREFIX)
            @agent_intake_http = build_http_client(
              agent_settings,
              compress: Ext::Transport::EVP_PROXY_COMPRESSION_SUPPORTED[path_prefix]
            )

            @agent_api_http = build_http_client(agent_settings, compress: false)

            path_prefix = "#{path_prefix}/" unless path_prefix.end_with?("/")
            @path_prefix = path_prefix
          end

          def citestcycle_request(path:, payload:, headers: {}, verb: "post")
            super

            headers[Ext::Transport::HEADER_EVP_SUBDOMAIN] = Ext::Transport::TEST_VISIBILITY_INTAKE_HOST_PREFIX

            perform_request(@agent_intake_http, path: path, payload: payload, headers: headers, verb: verb)
          end

          def api_request(path:, payload:, headers: {}, verb: "post")
            super

            headers[Ext::Transport::HEADER_EVP_SUBDOMAIN] = Ext::Transport::DD_API_HOST_PREFIX

            perform_request(@agent_api_http, path: path, payload: payload, headers: headers, verb: verb)
          end

          def citestcov_request(path:, payload:, headers: {}, verb: "post")
            super

            headers[Ext::Transport::HEADER_EVP_SUBDOMAIN] = Ext::Transport::TEST_COVERAGE_INTAKE_HOST_PREFIX

            perform_request(@agent_intake_http, path: path, payload: @citestcov_payload, headers: headers, verb: verb)
          end

          def logs_intake_request(path:, payload:, headers: {}, verb: "post")
            raise NotImplementedError, "Logs intake is not supported in EVP proxy mode"
          end

          private

          def perform_request(http_client, path:, payload:, headers:, verb:)
            http_client.request(
              path: path_with_prefix(path),
              payload: payload,
              headers: headers_with_default(headers),
              verb: verb
            )
          end

          def path_with_prefix(path)
            "#{@path_prefix}#{path.sub(/^\//, "")}"
          end

          def container_id
            return @container_id if defined?(@container_id)

            @container_id = Datadog::Core::Environment::Container.container_id
          end

          def default_headers
            headers = super

            c_id = container_id
            headers[Ext::Transport::HEADER_CONTAINER_ID] = c_id unless c_id.nil?

            headers
          end

          def build_http_client(agent_settings, compress:)
            Datadog::CI::Transport::HTTP.new(
              host: agent_settings.hostname,
              port: agent_settings.port,
              ssl: agent_settings.ssl,
              timeout: agent_settings.timeout_seconds,
              compress: compress
            )
          end
        end
      end
    end
  end
end
