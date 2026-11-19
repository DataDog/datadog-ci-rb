# frozen_string_literal: true

require_relative "reconfiguration"
require_relative "fallback"

module Datadog
  module CI
    module Configuration
      # Preserves the tracer configuration API when the optional tracer is loaded.
      module Extensions
        module LegacySettings
          def ci
            CI.configuration.ci
          end
        end

        module LazyConfiguration
          def configuration
            if !Extensions.tracer_active? && defined?(::Datadog::Core::Configuration::Settings)
              Extensions.activate!
            end
            super
          end
        end

        module TracerAccess
          private

          def tracer
            current = super
            components = CI.components(allow_initialization: false)
            components&.tracer_bridge&.observe(current) if current
            current
          end
        end

        def self.activate!
          unless defined?(::Datadog::Core::Configuration::Settings)
            ::Datadog.extend(Fallback)
            ::Datadog.singleton_class.prepend(LazyConfiguration)
            return false
          end

          ::Datadog::Core::Configuration::Settings.prepend(LegacySettings)
          ::Datadog.singleton_class.prepend(Reconfiguration)
          if defined?(::Datadog::Tracing) && ::Datadog::Tracing.respond_to?(:trace)
            ::Datadog::Tracing.singleton_class.prepend(TracerAccess)
            @tracer_active = true
          end
          true
        end

        def self.tracer_active?
          @tracer_active == true
        end

        def self.import_configuration!(settings)
          return unless ::Datadog.respond_to?(:configuration)

          source = ::Datadog.configuration
          return if source.equal?(settings)

          settings.import_legacy!(source)
        end
      end
    end
  end
end
