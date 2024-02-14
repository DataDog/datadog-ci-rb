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
            url = settings.ci.agentless_url ||
              "https://#{Ext::Transport::TEST_VISIBILITY_INTAKE_HOST_PREFIX}.#{dd_site}:443"

            uri = URI.parse(url)
            raise "Invalid agentless mode URL: #{url}" if uri.host.nil?

            http = Datadog::CI::Transport::HTTP.new(
              host: uri.host,
              port: uri.port,
              ssl: uri.scheme == "https" || uri.port == 443,
              compress: true
            )

            Agentless.new(api_key: settings.api_key, http: http)
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

            http = Datadog::CI::Transport::HTTP.new(
              host: agent_settings.hostname,
              port: agent_settings.port,
              ssl: agent_settings.ssl,
              timeout: agent_settings.timeout_seconds,
              compress: Ext::Transport::EVP_PROXY_COMPRESSION_SUPPORTED[evp_proxy_path_prefix]
            )

            EvpProxy.new(http: http, path_prefix: evp_proxy_path_prefix)
          end
        end
      end
    end
  end
end
