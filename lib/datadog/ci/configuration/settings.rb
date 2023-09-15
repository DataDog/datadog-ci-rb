# frozen_string_literal: true

require_relative "../ext/settings"

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to ddtrace settings
      module Settings
        InvalidIntegrationError = Class.new(StandardError)

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

                integration = fetch_integration(integration_name)
                return unless integration.class.compatible?

                return unless integration.default_configuration.enabled
                integration.configure(:default, options, &block)

                return if integration.patcher.patched?
                integration.patcher.patch
              end

              define_method(:[]) do |integration_name, key = :default|
                integration = fetch_integration(integration_name)

                integration.resolve(key) unless integration.nil?
              end

              # TODO: Deprecate in the next major version, as `instrument` better describes this method's purpose
              alias_method :use, :instrument

              option :trace_flush

              option :writer_options do |o|
                o.type :hash
                o.default({})
              end

              define_method(:fetch_integration) do |name|
                registered = Datadog::CI::Contrib::Integration.registry[name]
                raise(InvalidIntegrationError, "'#{name}' is not a valid integration.") if registered.nil?

                registered.integration
              end
            end
          end
        end
      end
    end
  end
end
