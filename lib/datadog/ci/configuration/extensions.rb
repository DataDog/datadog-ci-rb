# frozen_string_literal: true

require "datadog/core/configuration/settings"
require "datadog/core/configuration/components"

require_relative "settings"
require_relative "components"
require_relative "reconfiguration"

module Datadog
  module CI
    module Configuration
      # Extends Datadog tracing with CI features
      module Extensions
        def self.activate!
          Core::Configuration::Settings.extend(CI::Configuration::Settings)
          Core::Configuration::Components.prepend(CI::Configuration::Components)
          Datadog.singleton_class.prepend(CI::Configuration::Reconfiguration)
        end
      end
    end
  end
end
