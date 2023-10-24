# frozen_string_literal: true

require_relative "ci_test_cycle"
require_relative "evp_proxy"

module Datadog
  module CI
    module Transport
      module Api
        module Builder
          def self.build_ci_test_cycle_api(settings)
            dd_site = settings.site || Ext::Transport::DEFAULT_DD_SITE
            url = settings.ci.agentless_url ||
              "https://#{Ext::Transport::TEST_VISIBILITY_INTAKE_HOST_PREFIX}.#{dd_site}:443"

            CiTestCycle.new(api_key: settings.api_key, url: url)
          end

          def self.build_evp_proxy_api(agent_settings)
            EVPProxy.new(
              host: agent_settings.hostname,
              port: agent_settings.port,
              ssl: agent_settings.ssl,
              timeout: agent_settings.timeout_seconds
            )
          end
        end
      end
    end
  end
end
