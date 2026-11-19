# frozen_string_literal: true

require "logger"
require "monitor"

module Datadog
  module CI
    # Owns CI configuration and components independently of the application tracer.
    class Runtime
      def initialize(configuration: Configuration::RuntimeSettings.new)
        @configuration = configuration
        @components = nil
        @mutex = Monitor.new
        @default_logger = Logger.new($stderr)
      end

      def configuration
        return @configuration if @importing_configuration || configuration_locked?

        begin
          @importing_configuration = true
          Configuration::Extensions.import_configuration!(@configuration)
        ensure
          @importing_configuration = false
        end
        @configuration
      end

      def logger
        settings = configuration
        @default_logger.level = settings.diagnostics.debug ? Logger::DEBUG : settings.logger.level
        settings.logger.instance || @default_logger
      end

      def components(allow_initialization: true)
        @mutex.synchronize do
          return @components if @components || !allow_initialization

          @components = build_components
        end
      end

      def prepare_application_tracing!
        return if @components

        @mutex.synchronize do
          return if @components || @preparing_application_tracing || @building_components

          begin
            @preparing_application_tracing = true
            return unless @configuration.ci.enabled

            @components = build_components
            @bootstrap_components = true
          ensure
            @preparing_application_tracing = false
          end
        end
      rescue => error
        warn_safely("prepare application span capture", error)
      end

      def prepare_test_session(current)
        # @type var previous: Configuration::Components?
        previous = nil
        replacement = @mutex.synchronize do
          return current unless @bootstrap_components && @components&.test_tracing.equal?(current)

          @bootstrap_components = false
          previous = @components
          @components = build_components
        end
        previous&.shutdown!
        replacement.test_tracing
      rescue => error
        warn_safely("refresh CI configuration before the test session", error)
        @components&.test_tracing || current
      end

      def configure
        if configuration_locked?
          logger.warn("Test Optimization configuration is locked during an active test session.")
          return @configuration
        end

        yield @configuration
        configuration_changed!
        @configuration
      end

      def configuration_changed!
        previous = @mutex.synchronize do
          return if configuration_locked?

          current = @components
          @components = nil
          @bootstrap_components = false
          current
        end
        previous&.shutdown!
        nil
      end

      def shutdown!
        @bootstrap_components = false
        @components&.shutdown!
      end

      def reset!
        previous = @mutex.synchronize do
          current = @components
          @components = nil
          @bootstrap_components = false
          @configuration = Configuration::RuntimeSettings.new
          current
        end
        previous&.shutdown!
        nil
      end

      private

      def build_components
        @building_components = true
        Configuration::Extensions.import_configuration!(@configuration)
        Configuration::Components.new(@configuration)
      ensure
        @building_components = false
      end

      def warn_safely(action, error)
        logger.warn("Failed to #{action}: #{error.class}: #{error.message}")
      rescue
        nil
      end

      def configuration_locked?
        !!@components&.test_tracing&.configuration_locked?
      end
    end
  end
end
