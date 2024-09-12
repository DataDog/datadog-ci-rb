# frozen_string_literal: true

require_relative "integration"

module Datadog
  module CI
    module Contrib
      @@auto_instrumented_integrations = {}

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

            Datadog.logger.debug("Registering on require hook for #{name}...")

            @@auto_instrumented_integrations[name] = integration
          end
        end

        enable_trace_requires
      end

      def self.enable_trace_requires
        @@trp = TracePoint.new(:script_compiled) do |tp|
          on_require(tp.instruction_sequence.path)
        end

        @@trp.enable
      end

      def self.disable_trace_requires
        @@trp.disable
      end

      def self.on_require(path)
        Datadog.logger.debug { "Path: #{path}" }
        @@auto_instrumented_integrations.each do |gem_name, integration|
          if path.include?(gem_name.to_s) && integration.class.loaded?
            Datadog.logger.debug { "Gem '#{gem_name}' loaded. Configuring integration." }

            Contrib.disable_trace_requires

            configure_ci_with_framework(gem_name)
          end
        end
      rescue => e
        Datadog.logger.debug do
          "Failed to execute callback for gem: #{e.class.name} #{e.message} at #{Array(e.backtrace).join("\n")}"
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
