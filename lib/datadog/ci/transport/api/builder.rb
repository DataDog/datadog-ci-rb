# frozen_string_literal: true

require "uri"
require "json"

require_relative "agentless"
require_relative "evp_proxy"
require_relative "../http"
require_relative "../../ext/transport"

module Datadog
  module CI
    module Transport
      module Api
        module Builder
          def self.build_agentless_api(settings)
            return nil if settings.api_key.nil?

            dd_site = settings.site || Ext::Transport::DEFAULT_DD_SITE

            citestcycle_url = settings.ci.agentless_url ||
              "https://#{Ext::Transport::TEST_VISIBILITY_INTAKE_HOST_PREFIX}.#{dd_site}:443"

            api_url = settings.ci.agentless_url ||
              "https://#{Ext::Transport::DD_API_HOST_PREFIX}.#{dd_site}:443"

            citestcov_url = settings.ci.agentless_url ||
              "https://#{Ext::Transport::TEST_COVERAGE_INTAKE_HOST_PREFIX}.#{dd_site}:443"

            logs_intake_url = settings.ci.agentless_url ||
              "https://#{Ext::Transport::LOGS_INTAKE_HOST_PREFIX}.#{dd_site}:443"

            cicovreprt_url = settings.ci.agentless_url ||
              "https://#{Ext::Transport::CODE_COVERAGE_REPORT_INTAKE_HOST_PREFIX}.#{dd_site}:443"

            Agentless.new(
              api_key: settings.api_key,
              citestcycle_url: citestcycle_url,
              api_url: api_url,
              citestcov_url: citestcov_url,
              logs_intake_url: logs_intake_url,
              cicovreprt_url: cicovreprt_url
            )
          end

          def self.build_evp_proxy_api(settings)
            agent_settings = resolve_agent_settings(settings)
            response = Transport::HTTP.new(
              host: agent_settings.hostname,
              port: agent_settings.port,
              ssl: agent_settings.ssl,
              timeout: agent_settings.timeout_seconds,
              uds_path: agent_settings.uds_path
            ).request(path: "/info", payload: nil, headers: {}, verb: "get")

            return [nil, false] if response.error

            endpoints = JSON.parse(response.payload).fetch("endpoints", []) if response.ok?
            evp_proxy_path_prefix = if response.ok? && endpoints.is_a?(Array)
              Ext::Transport::EVP_PROXY_PATH_PREFIXES.find { |path_prefix| endpoints.include?(path_prefix) }
            end

            return [nil, true] if evp_proxy_path_prefix.nil?

            [EvpProxy.new(agent_settings: agent_settings, path_prefix: evp_proxy_path_prefix), true]
          rescue JSON::ParserError, URI::InvalidURIError => error
            CI.logger.warn("Failed to read Datadog Agent configuration: #{error}")
            [nil, false]
          end

          AgentSettings = Struct.new(:hostname, :port, :ssl, :timeout_seconds, :uds_path, keyword_init: true)

          def self.resolve_agent_settings(settings)
            agent = settings.agent
            url = agent.url && URI.parse(agent.url)
            socket = agent.uds_path || (url.path if url && url.scheme == "unix")
            if !url && !agent.host && !agent.port && !socket && File.socket?("/var/run/datadog/apm.socket")
              socket = "/var/run/datadog/apm.socket"
            end
            AgentSettings.new(
              hostname: agent.host || (url.host if url) || "127.0.0.1",
              port: agent.port || (url.port if url.respond_to?(:port)) || 8126,
              ssl: agent.use_ssl || (url && url.scheme == "https") || false,
              timeout_seconds: agent.timeout_seconds,
              uds_path: socket
            )
          end
        end
      end
    end
  end
end
