# frozen_string_literal: true

require "datadog/core/configuration/agent_settings_resolver"
require "datadog/core/remote/transport/http"

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
            agent_settings = Datadog::Core::Configuration::AgentSettingsResolver.call(settings)
            response = Datadog::Core::Remote::Transport::HTTP.root(
              agent_settings: agent_settings,
              logger: Datadog.logger
            ).send_info

            return [nil, false] if response.internal_error?

            endpoints = response.endpoints
            evp_proxy_path_prefix = if response.ok? && endpoints.is_a?(Array)
              Ext::Transport::EVP_PROXY_PATH_PREFIXES.find { |path_prefix| endpoints.include?(path_prefix) }
            end

            return [nil, true] if evp_proxy_path_prefix.nil?

            [EvpProxy.new(agent_settings: agent_settings, path_prefix: evp_proxy_path_prefix), true]
          end
        end
      end
    end
  end
end
