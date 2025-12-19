# frozen_string_literal: true

require_relative "../integration"
require_relative "configuration/settings"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Minitest
        # Description of Minitest integration
        class Integration < Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("5.0.0")

          def version
            Gem.loaded_specs["minitest"]&.version
          end

          def loaded?
            !defined?(::Minitest).nil? && !defined?(::Minitest::Runnable).nil? && !defined?(::Minitest::Test).nil? &&
              !defined?(::Minitest::CompositeReporter).nil? && !defined?(::Minitest::Parallel::Executor).nil?
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
