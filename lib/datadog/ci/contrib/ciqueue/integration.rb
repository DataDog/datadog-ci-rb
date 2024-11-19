# frozen_string_literal: true

require_relative "../integration"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module Ciqueue
        # ci-queue test runner instrumentation
        # https://github.com/Shopify/ci-queue
        class Integration < Contrib::Integration
          MINIMUM_VERSION = Gem::Version.new("0.9.0")

          def version
            Gem.loaded_specs["ci-queue"]&.version
          end

          def loaded?
            !defined?(::RSpec::Queue::Runner).nil?
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
