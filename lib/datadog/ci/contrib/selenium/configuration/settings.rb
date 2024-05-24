# frozen_string_literal: true

require "datadog/core"

require_relative "../ext"
require_relative "../../settings"

module Datadog
  module CI
    module Contrib
      module Selenium
        module Configuration
          # Custom settings for the Selenium integration
          # @public_api
          class Settings < Datadog::CI::Contrib::Settings
            option :enabled do |o|
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end
          end
        end
      end
    end
  end
end
