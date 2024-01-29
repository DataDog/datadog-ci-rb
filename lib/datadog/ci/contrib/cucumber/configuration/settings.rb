# frozen_string_literal: true

require "datadog/core"

require_relative "../ext"
require_relative "../../settings"
require_relative "../../../utils/configuration"

module Datadog
  module CI
    module Contrib
      module Cucumber
        module Configuration
          # Custom settings for the Cucumber integration
          # @public_api
          class Settings < Datadog::CI::Contrib::Settings
            option :enabled do |o|
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end

            option :service_name do |o|
              o.type :string
              o.default do
                Utils::Configuration.fetch_service_name(Ext::DEFAULT_SERVICE_NAME)
              end
            end
          end
        end
      end
    end
  end
end
