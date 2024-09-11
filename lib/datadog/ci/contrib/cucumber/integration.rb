# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Description of Cucumber integration
        class Integration
          include Datadog::CI::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new("3.0.0")

          register_as :cucumber

          def self.version
            Gem.loaded_specs["cucumber"]&.version
          end

          def self.loaded?
            !defined?(::Cucumber).nil? && !defined?(::Cucumber::Runtime).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def requires
            ["cucumber"]
          end

          def auto_instrument?
            true
          end

          def instrument_on_session_start?
            false
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
