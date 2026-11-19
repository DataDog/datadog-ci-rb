# frozen_string_literal: true

module Datadog
  module CI
    # Runs one background operation per process.
    class Worker
      DEFAULT_SHUTDOWN_TIMEOUT = 60

      def initialize(&operation)
        @operation = operation
        @pid = Process.pid
        @mutex = Mutex.new
        @thread = nil
      end

      def perform(*arguments)
        if @pid != Process.pid
          @pid = Process.pid
          @mutex = Mutex.new
          @thread = nil
        end
        @mutex.synchronize do
          return if @thread
          @thread = Thread.new do
            @operation.call(*arguments)
          rescue => error
            CI.logger.warn("Test Optimization worker failed: #{error}")
          end
        end
      end

      def stop(timeout = DEFAULT_SHUTDOWN_TIMEOUT)
        wait_until_done(timeout)
      end

      def wait_until_done(timeout = nil)
        @thread&.join(timeout) unless @thread == Thread.current
      end

      def started?
        !@thread.nil?
      end

      def running?
        !!@thread&.alive?
      end

      def done?
        started? && !running?
      end
    end

    class DummyWorker < Worker
      def initialize
        super { nil }
      end
    end
  end
end
