# frozen_string_literal: true

require_relative "integration"

module Datadog
  module CI
    module Contrib
      def self.auto_instrument!
        Datadog.logger.debug("Auto instrumenting all integrations...")

        Integration.registry.each do |name, integration|
          next unless integration.auto_instrument?

          Datadog.logger.debug "#{name} is allowed to be auto instrumented"

          if integration.class.loaded?
            Datadog.logger.debug("#{name} is already loaded")

            configure_ci_with_framework(name)
          else
            Datadog.logger.debug("#{name} is not loaded yet")

            integration.requires.each do |require_path|
              Datadog.logger.debug("Registering on require hook for #{require_path}...")

              ::Kernel.on_require(require_path) do
                configure_ci_with_framework(name)
              end
            end
          end
        end
      end

      def self.configure_ci_with_framework(framework)
        Datadog.logger.debug("Configuring CI with #{framework}...")

        Datadog.configure do |c|
          c.tracing.enabled = true
          c.ci.enabled = true
          c.ci.instrument framework
        end
      end

      # This method auto instruments all test libraries (ex: selenium-webdriver).
      # It is intended to be called when test session starts to add additional capabilities to test visibility.
      #
      # This method does not automatically instrument test frameworks (ex: RSpec, Cucumber, etc), it requires
      # test framework to be already instrumented.
      def self.instrument_on_session_start!
        Datadog.logger.debug("Instrumenting additional libraries when session starts...")

        Integration.registry.each do |name, integration|
          next unless integration.instrument_on_session_start?

          Datadog.logger.debug "#{name} is allowed to be instrumented when session starts"

          patch_results = integration.patch
          if patch_results == true
            Datadog.logger.debug("#{name} is patched")
          else
            Datadog.logger.debug("#{name} is not patched (#{patch_results})")
          end
        end
      end
    end
  end
end
