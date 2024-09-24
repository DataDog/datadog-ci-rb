# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Simplecov
        # Description of Simplecov integration
        class Integration
          include Datadog::CI::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new("0.18.0")

          register_as :simplecov

          def self.version
            Gem.loaded_specs["simplecov"]&.version
          end

          def self.loaded?
            !defined?(::SimpleCov).nil?
          end

          def self.compatible?
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
