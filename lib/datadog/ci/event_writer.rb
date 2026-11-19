# frozen_string_literal: true

module Datadog
  module CI
    # Buffers completed CI events and sends them outside the test thread.
    class EventWriter
      attr_reader :transport

      def initialize(transport:, logger:, buffer_size: 10_000, flush_interval: 1.0, shutdown_timeout: 60)
        @transport = transport
        @logger = logger
        @buffer_size = buffer_size
        @flush_interval = flush_interval
        @shutdown_timeout = shutdown_timeout
        reset_process_state
      end

      def write(trace)
        reset_process_state if @pid != Process.pid
        @mutex.synchronize do
          return false if @stopped
          if @buffer.size >= @buffer_size
            @logger.warn("Test Optimization event buffer is full. Dropping a trace.")
            return false
          end
          @buffer << trace
          start_worker unless @worker&.alive?
          @condition.signal if @buffer.size >= 100
        end
        true
      rescue => error
        @logger.warn("Failed to buffer Test Optimization events: #{error}")
        false
      end

      def flush
        reset_process_state if @pid != Process.pid
        @send_mutex.synchronize do
          events = @mutex.synchronize do
            pending = @buffer
            @buffer = []
            pending
          end
          @transport.send_traces(events) unless events.empty?
        end
        nil
      rescue => error
        @logger.warn("Failed to send Test Optimization events: #{error}")
        nil
      end

      def shutdown!
        reset_process_state if @pid != Process.pid
        worker = @mutex.synchronize do
          @stopped = true
          @condition.broadcast
          @worker
        end
        if worker
          worker.join(@shutdown_timeout)
          @logger.warn("Test Optimization event shutdown timed out.") if worker.alive?
        else
          flush
        end
        nil
      end

      alias_method :stop, :shutdown!

      def running?
        !!@worker&.alive? && !@stopped
      end

      def started?
        !@worker.nil?
      end

      def stopped?
        @stopped
      end

      private

      def reset_process_state
        @pid = Process.pid
        @mutex = Mutex.new
        @send_mutex = Mutex.new
        @condition = ConditionVariable.new
        @buffer = []
        @worker = nil
        @stopped = false
      end

      def start_worker
        worker = Thread.new do
          loop do
            stopped = @mutex.synchronize do
              @condition.wait(@mutex, @flush_interval) unless @stopped || @buffer.size >= 100
              @stopped
            end
            flush
            break if stopped
          end
        rescue => error
          @logger.warn("Test Optimization event worker failed: #{error}")
        end
        worker.name = "datadog-ci-events" if worker.respond_to?(:name=)
        @worker = worker
      end
    end
  end
end
