# frozen_string_literal: true

require_relative "../ext"
require_relative "../../settings"
require_relative "../../../utils/configuration"

module Datadog
  module CI
    module Contrib
      module RSpec
        module Configuration
          # Custom settings for the RSpec integration
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

            option :datadog_formatter_enabled do |o|
              o.type :bool
              o.env Ext::ENV_DATADOG_FORMATTER_ENABLED
              o.default true
            end

            # internal only
            option :dry_run_enabled do |o|
              o.type :bool
              o.default false
            end
          end
        end
      end
    end
  end
end
