# frozen_string_literal: true

require "monitor"

module Datadog
  module CI
    module Utils
      # Shared by tracing and coverage. Only instrumentation transitions run
      # under this monitor; customer test bodies must never hold it.
      class TestExecution
        def initialize
          @pid = Process.pid
          @owner = nil
          @disabled = false
          @monitor = Monitor.new
          @disable_callbacks = []
        end

        def synchronize
          reset_after_fork
          @monitor.synchronize do
            return if @disabled

            @owner ||= Fiber.current
            unless @owner.equal?(Fiber.current)
              disable!("test lifecycle moved to another thread or fiber")
              return
            end

            yield
          end
        end

        def enabled?
          reset_after_fork
          !@disabled
        end

        def disable!(reason)
          reset_after_fork
          @monitor.synchronize do
            return if @disabled

            @disabled = true
            Datadog.logger.warn(
              "Test Optimization disabled for this process: #{reason}. " \
              "Tests and framework hooks must run sequentially on one Ruby fiber. " \
              "Use a sequential or process-based test executor; application background threads are supported."
            )
            @disable_callbacks.each(&:call)
          end
          nil
        end

        def on_disable(&block)
          @disable_callbacks << block
        end

        private

        def reset_after_fork
          return if @pid == Process.pid

          @pid = Process.pid
          @owner = nil
          @disabled = false
          @monitor = Monitor.new
        end
      end
    end
  end
end
