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

            # @deprecated Will be removed in 1.0
            option :operation_name do |o|
              o.type :string
              o.env Ext::ENV_OPERATION_NAME
              o.default Ext::OPERATION_NAME

              o.after_set do |value|
                if value && value != Ext::OPERATION_NAME
                  Datadog::Core.log_deprecation do
                    "The operation_name setting has no effect and will be removed in 1.0"
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
