# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Lograge
        # Description of Lograge integration
        class Integration < Datadog::CI::Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("0.14.0")

          def version
            Gem.loaded_specs["lograge"]&.version
          end

          def loaded?
            !defined?(::Lograge).nil? && !defined?(::Lograge::LogSubscribers).nil? &&
              !defined?(::Lograge::LogSubscribers::Base).nil?
          end

          def compatible?
            super && version && version >= MINIMUM_VERSION
          end

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
