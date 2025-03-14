# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module ParallelTests
        # Description of ParallelTests integration
        class Integration < Datadog::CI::Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("5.1.0")

          def version
            Gem.loaded_specs["parallel_tests"]&.version
          end

          def loaded?
            !defined?(::ParallelTests).nil? && !defined?(::ParallelTests::CLI).nil?
          end

          def compatible?
            super && version >= MINIMUM_VERSION
          end

          def late_instrument?
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
