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
        @default_logger.level = @configuration.diagnostics.debug ? Logger::DEBUG : @configuration.logger.level
        @configuration.logger.instance || @default_logger
      end

      def components(allow_initialization: true)
        @mutex.synchronize do
          return @components if @components || !allow_initialization

          Configuration::Extensions.import_configuration!(@configuration)
          @components = Configuration::Components.new(@configuration)
        end
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
          current
        end
        previous&.shutdown!
        nil
      end

      def shutdown!
        @components&.shutdown!
      end

      def reset!
        previous = @mutex.synchronize do
          current = @components
          @components = nil
          @configuration = Configuration::RuntimeSettings.new
          current
        end
        previous&.shutdown!
        nil
      end

      private

      def configuration_locked?
        !!@components&.test_tracing&.configuration_locked?
      end
    end
  end
end
