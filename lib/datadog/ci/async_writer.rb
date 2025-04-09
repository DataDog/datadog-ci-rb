# frozen_string_literal: true

require "datadog/core/workers/async"
require "datadog/core/workers/queue"
require "datadog/core/workers/polling"

require "datadog/core/buffer/cruby"
require "datadog/core/buffer/thread_safe"

require "datadog/core/environment/ext"

module Datadog
  module CI
    class AsyncWriter
      include Core::Workers::Queue
      include Core::Workers::Polling

      attr_reader :transport

      DEFAULT_BUFFER_MAX_SIZE = 10_000
      DEFAULT_SHUTDOWN_TIMEOUT = 60

      DEFAULT_INTERVAL = 3

      def initialize(transport:, options: {})
        @transport = transport

        # Workers::Polling settings
        self.enabled = options.fetch(:enabled, true)

        # Workers::Async::Thread settings
        self.fork_policy = Core::Workers::Async::Thread::FORK_POLICY_RESTART

        # Workers::IntervalLoop settings
        self.loop_base_interval = options[:interval] || DEFAULT_INTERVAL
        self.loop_back_off_ratio = options[:back_off_ratio] if options.key?(:back_off_ratio)
        self.loop_back_off_max = options[:back_off_max] if options.key?(:back_off_max)

        @buffer_size = options.fetch(:buffer_size, DEFAULT_BUFFER_MAX_SIZE)

        self.buffer = buffer_klass.new(@buffer_size)

        @shutdown_timeout = options.fetch(:shutdown_timeout, DEFAULT_SHUTDOWN_TIMEOUT)

        @stopped = false
      end

      def write(event)
        return if @stopped

        # Start worker thread. If the process has forked, it will trigger #after_fork to
        # reconfigure the worker accordingly.
        perform

        enqueue(event)
      end

      def perform(*events)
        responses = transport.send_events(events)

        if responses.find(&:server_error?)
          loop_back_off!
          Datadog.logger.warn { "Encountered server error while sending events: #{responses}" }
        end

        nil
      rescue => e
        Datadog.logger.warn { "Error while sending events: #{e}" }
        loop_back_off!
      end

      def stop(force_stop = false, timeout = @shutdown_timeout)
        @stopped = true

        buffer.close if running?

        super
      end

      def enqueue(event)
        buffer.push(event)
      end

      def dequeue
        buffer.pop
      end

      def work_pending?
        !buffer.empty?
      end

      def async?
        true
      end

      def after_fork
        # In multiprocess environments, forks will share the same buffer until its written to.
        # A.K.A. copy-on-write. We don't want forks to write events generated from another process.
        # Instead, we reset it after the fork. (Make sure any enqueue operations happen after this.)
        self.buffer = buffer_klass.new(@buffer_size)
      end

      def buffer_klass
        if Core::Environment::Ext::RUBY_ENGINE == "ruby"
          Core::Buffer::CRuby
        else
          Core::Buffer::ThreadSafe
        end
      end
    end
  end
end
