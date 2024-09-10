# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Selenium
        # Description of Selenium integration
        class Integration
          include Datadog::CI::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new("4.0.0")

          register_as :selenium

          def self.version
            Gem.loaded_specs["selenium-webdriver"]&.version
          end

          def self.loaded?
            !defined?(::Selenium).nil? && !defined?(::Selenium::WebDriver).nil? &&
              !defined?(::Selenium::WebDriver::Driver).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          # additional instrumentations for test helpers are auto instrumented on test session start
          def auto_instrument?
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
