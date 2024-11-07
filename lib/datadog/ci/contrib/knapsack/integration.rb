# frozen_string_literal: true

require_relative "../integration"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Knapsack
        # Knapsack Pro test runner instrumentation
        # https://github.com/KnapsackPro/knapsack_pro-ruby
        class Integration
          include Datadog::CI::Contrib::Integration

          Configuration = Struct.new(:enabled)

          MINIMUM_VERSION = Gem::Version.new("7.0.0")

          register_as :knapsack

          def self.version
            Gem.loaded_specs["knapsack_pro"]&.version
          end

          def self.loaded?
            !defined?(::KnapsackPro).nil? && !defined?(::KnapsackPro::Extensions::RSpecExtension).nil? &&
              !defined?(::KnapsackPro::Extensions::RSpecExtension::Runner).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          # test environments should not auto instrument test libraries
          def auto_instrument?
            false
          end

          # TODO: not every integration needs a configuration
          def new_configuration
            Integration::Configuration.new(true)
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
