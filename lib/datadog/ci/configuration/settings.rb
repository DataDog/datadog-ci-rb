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

              option :agentless_mode_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_AGENTLESS_MODE_ENABLED
                o.default false
              end

              option :agentless_url do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Settings::ENV_AGENTLESS_URL
              end

              option :force_test_level_visibility do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_FORCE_TEST_LEVEL_VISIBILITY
                o.default false
              end

              option :experimental_test_suite_level_visibility_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_EXPERIMENTAL_TEST_SUITE_LEVEL_VISIBILITY_ENABLED
                o.default false
                o.after_set do |value|
                  if value
                    Datadog::Core.log_deprecation do
                      "The experimental_test_suite_level_visibility_enabled setting has no effect and will be removed in 2.0. " \
                        "Test suite level visibility is now enabled by default. " \
                        "If you want to disable test suite level visibility set configuration.ci.force_test_level_visibility = true."
                    end
                  end
                end
              end

              define_method(:instrument) do |integration_name, options = {}, &block|
                return unless enabled

                integration = fetch_integration(integration_name)
                integration.configure(options, &block)

                return unless integration.enabled

                patch_results = integration.patch
                next if patch_results == true

                error_message = <<-ERROR
                  Available?: #{patch_results[:available]}, Loaded?: #{patch_results[:loaded]},
                  Compatible?: #{patch_results[:compatible]}, Patchable?: #{patch_results[:patchable]}"
                ERROR
                Datadog.logger.warn("Unable to patch #{integration_name} (#{error_message})")
              end

              define_method(:[]) do |integration_name|
                fetch_integration(integration_name).configuration
              end

              # @deprecated Will be removed on datadog-ci-rb 1.0.
              alias_method :use, :instrument

              option :trace_flush

              option :writer_options do |o|
                o.type :hash
                o.default({})
              end

              define_method(:fetch_integration) do |name|
                Datadog::CI::Contrib::Integration.registry[name] ||
                  raise(InvalidIntegrationError, "'#{name}' is not a valid integration.")
              end
            end
          end
        end
      end
    end
  end
end
