# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Selenium
        # Description of Selenium integration
        class Integration < Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("4.0.0")

          def version
            Gem.loaded_specs["selenium-webdriver"]&.version
          end

          def loaded?
            !defined?(::Selenium).nil? && !defined?(::Selenium::WebDriver).nil? &&
              !defined?(::Selenium::WebDriver::Driver).nil?
          end

          def compatible?
            super && version >= MINIMUM_VERSION
          end

          # additional instrumentations for test helpers are auto instrumented on test session start
          def auto_instrument?
            true
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
