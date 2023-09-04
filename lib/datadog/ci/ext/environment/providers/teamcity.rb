# frozen_string_literal: true

require_relative "../extractor"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # Teamcity: https://www.jetbrains.com/teamcity/
          # Environment variables docs: https://www.jetbrains.com/help/teamcity/predefined-build-parameters.html
          class Teamcity < Extractor
            private

            # overridden methods
            def provider_name
              "teamcity"
            end

            def job_name
              env["TEAMCITY_BUILDCONF_NAME"]
            end

            def job_url
              env["BUILD_URL"]
            end
          end
        end
      end
    end
  end
end
