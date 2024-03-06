# frozen_string_literal: true

require "datadog/core/configuration/agent_settings_resolver"
require "datadog/core/remote/negotiation"

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

            Agentless.new(api_key: settings.api_key, citestcycle_url: citestcycle_url, api_url: api_url)
          end

          def self.build_evp_proxy_api(settings)
            agent_settings = Datadog::Core::Configuration::AgentSettingsResolver.call(settings)
            negotiation = Datadog::Core::Remote::Negotiation.new(settings, agent_settings)

            # temporary, remove this when patch will be accepted in Core to make logging configurable
            negotiation.instance_variable_set(:@logged, {no_config_endpoint: true})

            evp_proxy_path_prefix = Ext::Transport::EVP_PROXY_PATH_PREFIXES.find do |path_prefix|
              negotiation.endpoint?(path_prefix)
            end

            return nil if evp_proxy_path_prefix.nil?

            EvpProxy.new(agent_settings: agent_settings, path_prefix: evp_proxy_path_prefix)
          end
        end
      end
    end
  end
end
