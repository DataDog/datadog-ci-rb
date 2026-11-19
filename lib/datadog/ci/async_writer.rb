# frozen_string_literal: true

require_relative "event_writer"

module Datadog
  module CI
    class AsyncWriter
      DEFAULT_BUFFER_MAX_SIZE = 10_000
      DEFAULT_SHUTDOWN_TIMEOUT = 60
      DEFAULT_INTERVAL = 3

      class EventTransport
        def initialize(transport)
          @transport = transport
        end

        def send_traces(events)
          @transport.send_events(events)
        end
      end

      attr_reader :transport

      def initialize(transport:, options: {})
        @transport = transport
        @writer = EventWriter.new(
          transport: EventTransport.new(transport),
          logger: CI.logger,
          buffer_size: options.fetch(:buffer_size, DEFAULT_BUFFER_MAX_SIZE),
          flush_interval: options.fetch(:interval, DEFAULT_INTERVAL),
          shutdown_timeout: options.fetch(:shutdown_timeout, DEFAULT_SHUTDOWN_TIMEOUT)
        )
      end

      def write(event)
        @writer.write(event)
      end

      def perform(*events)
        @transport.send_events(events)
        nil
      rescue => error
        CI.logger.warn("Failed to send Test Optimization events: #{error}")
        nil
      end

      def stop(_force_stop = false, _timeout = DEFAULT_SHUTDOWN_TIMEOUT)
        @writer.shutdown!
      end

      def flush
        @writer.flush
      end

      def started?
        @writer.started?
      end

      def running?
        @writer.running?
      end

      def async?
        true
      end
    end
  end
end
