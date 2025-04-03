# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module ActiveSupport
        # Description of ActiveSupport integration
        class Integration < Datadog::CI::Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("5.0")

          def version
            Gem.loaded_specs["activesupport"]&.version
          end

          def loaded?
            !defined?(::Rails).nil? && !defined?(::ActiveSupport).nil? && !defined?(::ActiveSupport::TaggedLogging).nil? &&
              !defined?(::ActiveSupport::TaggedLogging::Formatter).nil?
          end

          def compatible?
            super && version >= MINIMUM_VERSION
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
