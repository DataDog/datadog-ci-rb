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
              !defined?(::RSpec::Core::ExampleGroup).nil? &&
              !defined?(::RSpec::Core::Formatters::DocumentationFormatter).nil? &&
              !defined?(::RSpec::Core::Formatters::BaseFormatter).nil? &&
              !defined?(::RSpec::Core::Formatters::BaseTextFormatter).nil?
          end

          def compatible?
            super && version >= MINIMUM_VERSION
          end

          def new_configuration
            settings = Configuration::Settings.new
            # if we are running in test discovery mode, we are most likely running in dry run - we need to allow it
            settings.dry_run_enabled = true if test_discovery_component&.enabled?
            settings
          end

          def patcher
            Patcher
          end

          def test_discovery_component
            Datadog.send(:components).test_discovery
          end
        end
      end
    end
  end
end
