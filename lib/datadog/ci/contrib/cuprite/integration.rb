# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Cuprite
        # Description of Cuprite integration
        class Integration < Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("0.15.0")

          def version
            Gem.loaded_specs["cuprite"]&.version
          end

          def loaded?
            !defined?(::Capybara).nil? && !defined?(::Capybara::Cuprite).nil? &&
              !defined?(::Capybara::Cuprite::Driver).nil?
          end

          def compatible?
            super && version >= MINIMUM_VERSION
          end

          # additional instrumentations for test libraries are late instrumented on test session start
          def late_instrument?
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
