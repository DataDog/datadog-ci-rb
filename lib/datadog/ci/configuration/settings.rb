# frozen_string_literal: true

require_relative "../ext/settings"

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to Datadog trace settings
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.add_settings!(base)
          base.class_eval do
            settings :ci do
              option :enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_MODE_ENABLED
                o.default false
              end

              define_method(:instrument) do |integration_name, options = {}, &block|
                return unless enabled

                registered_integration = Datadog::CI::Contrib::Integration.registry[integration_name]
                return unless registered_integration

                klass = registered_integration.klass
                return unless klass.loaded? && klass.compatible?

                instance = klass.new
                return if instance.patcher.patched?

                instance.patcher.patch
              end

              # TODO: Deprecate in the next major version, as `instrument` better describes this method's purpose
              alias_method :use, :instrument

              option :trace_flush

              option :writer_options do |o|
                o.type :hash
                o.default({})
              end
            end
          end
        end
      end
    end
  end
end
