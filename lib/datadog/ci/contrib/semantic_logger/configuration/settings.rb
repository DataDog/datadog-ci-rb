# frozen_string_literal: true

require_relative "../ext"
require_relative "../../settings"
require_relative "../../../utils/configuration"

module Datadog
  module CI
    module Contrib
      module SemanticLogger
        module Configuration
          # Custom settings for the SemanticLogger integration
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
