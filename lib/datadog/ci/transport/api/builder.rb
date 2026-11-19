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
            ).request(path: "/info", payload: "", headers: {}, verb: "get")

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
            url = parse_agent_url(agent.url)
            http_url = url if url.is_a?(URI::HTTP)
            host = agent.host || http_url&.hostname || agent.host_from_environment
            port = parse_agent_integer(agent.port, "agent.port") || http_url&.port ||
              parse_agent_integer(agent.port_from_environment, "DD_TRACE_AGENT_PORT")
            socket = agent.uds_path
            socket ||= url.to_s.sub(/\Aunix:(?:\/\/)?/, "") if url && url.scheme == "unix"
            if !host && !port && !socket && File.socket?("/var/run/datadog/apm.socket")
              socket = "/var/run/datadog/apm.socket"
            end
            ssl = agent.use_ssl.nil? ? url&.scheme == "https" : agent.use_ssl
            timeout = parse_agent_timeout(agent.timeout_seconds, "agent.timeout_seconds") ||
              parse_agent_timeout(agent.timeout_from_environment, "DD_TRACE_AGENT_TIMEOUT_SECONDS") || 30
            AgentSettings.new(
              hostname: host || "127.0.0.1",
              port: port || 8126,
              ssl: socket ? false : ssl,
              timeout_seconds: timeout,
              uds_path: socket
            )
          end

          def self.parse_agent_url(value)
            return if value.nil?

            url = URI.parse(value)
            return url if ["http", "https", "unix"].include?(url.scheme)

            CI.logger.warn("Ignoring Datadog Agent URL with unsupported scheme: #{url.scheme}")
            nil
          rescue URI::InvalidURIError => error
            CI.logger.warn("Ignoring invalid Datadog Agent URL: #{error}")
            nil
          end

          def self.parse_agent_timeout(value, name)
            return if value.nil?

            parsed = Float(value, exception: false)
            return parsed if parsed&.finite? && parsed >= 0

            CI.logger.warn("Ignoring invalid Datadog Agent setting #{name}: #{value.inspect}")
            nil
          end

          def self.parse_agent_integer(value, name)
            return if value.nil?

            parsed = Integer(value, exception: false)
            CI.logger.warn("Ignoring invalid Datadog Agent setting #{name}: #{value.inspect}") if parsed.nil?
            parsed
          end
        end
      end
    end
  end
end
