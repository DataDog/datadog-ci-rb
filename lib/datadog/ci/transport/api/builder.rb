# frozen_string_literal: true

require_relative "ci_intake"

module Datadog
  module CI
    module Transport
      module Api
        module Builder
          def self.build_ci_test_cycle_api(settings)
            dd_site = settings.site || "datadoghq.com"
            url = settings.ci.agentless_url ||
              "https://#{Ext::Transport::TEST_VISIBILITY_INTAKE_HOST_PREFIX}.#{dd_site}:443"

            CIIntake.new(api_key: settings.api_key, url: url)
          end
        end
      end
    end
  end
end
