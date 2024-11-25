# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Description of Cucumber integration
        class Integration < Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("3.0.0")

          def version
            Gem.loaded_specs["cucumber"]&.version
          end

          def loaded?
            !defined?(::Cucumber).nil? && !defined?(::Cucumber::Runtime).nil? && !defined?(::Cucumber::Configuration).nil?
          end

          def compatible?
            super && version >= MINIMUM_VERSION
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
