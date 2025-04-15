# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module SemanticLogger
        # Description of SemanticLogger integration
        class Integration < Datadog::CI::Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("4.0")

          def version
            Gem.loaded_specs["semantic_logger"]&.version
          end

          def loaded?
            !defined?(::SemanticLogger).nil? && !defined?(::SemanticLogger::Logger).nil?
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
