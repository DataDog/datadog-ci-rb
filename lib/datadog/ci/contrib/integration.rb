# frozen_string_literal: true

require "datadog/tracing/contrib/configurable"
require "datadog/tracing/contrib/patchable"

module Datadog
  module CI
    module Contrib
      module Integration
        @registry = {}

        RegisteredIntegration = Struct.new(:name, :integration, :options)

        def self.included(base)
          base.extend(ClassMethods)

          base.include(Datadog::Tracing::Contrib::Patchable)
          base.include(Datadog::Tracing::Contrib::Configurable)
        end

        # Class-level methods for Integration
        module ClassMethods
          def register_as(name, options = {})
            Integration.register(self, name, options)
          end
        end

        def self.register(klass, name, options)
          registry[name] = RegisteredIntegration.new(name, klass.new, options)
        end

        def self.registry
          @registry
        end
      end
    end
  end
end
