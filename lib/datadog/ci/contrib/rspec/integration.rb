# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module RSpec
        # Description of RSpec integration
        class Integration < Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("3.0.0")

          def dependants
            %i[knapsack ciqueue]
          end

          def version
            Gem.loaded_specs["rspec-core"]&.version
          end

          def loaded?
            !defined?(::RSpec).nil? && !defined?(::RSpec::Core).nil? &&
              !defined?(::RSpec::Core::Example).nil? &&
              !defined?(::RSpec::Core::Runner).nil? &&
              !defined?(::RSpec::Core::ExampleGroup).nil?
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

          def test_discovery_component
            components = Datadog.send(:components)
            return nil unless components.respond_to?(:test_discovery)
            components.test_discovery
          end
        end
      end
    end
  end
end
