# frozen_string_literal: true

require_relative "../integration"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Knapsack
        # Knapsack Pro test runner instrumentation
        # https://github.com/KnapsackPro/knapsack_pro-ruby
        class Integration < Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("7.0.0")

          def version
            Gem.loaded_specs["knapsack_pro"]&.version
          end

          def loaded?
            !defined?(::KnapsackPro).nil? &&
              !defined?(::KnapsackPro::Extensions::RSpecExtension).nil? &&
              !defined?(::KnapsackPro::Extensions::RSpecExtension::Runner).nil? &&
              !defined?(::KnapsackPro::TestCaseDetectors::RSpecTestExampleDetector).nil? &&
              !defined?(::KnapsackPro::Adapters::RSpecAdapter).nil? &&
              !defined?(::KnapsackPro::TestSuite).nil?
          end

          def compatible?
            super && version >= MINIMUM_VERSION
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
