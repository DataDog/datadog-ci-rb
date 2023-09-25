require_relative "workers"
require_relative "test_visibility/transport"

module Datadog
  module CI
    # Processor that sends traces and metadata to the agent
    class Writer
      attr_reader \
        :transport,
        :worker

      def initialize(options = {})
        # writer and transport parameters
        @buff_size = options.fetch(
          :buffer_size,
          Datadog::Tracing::Workers::AsyncTransport::DEFAULT_BUFFER_MAX_SIZE
        )
        @flush_interval = options.fetch(
          :flush_interval,
          Datadog::Tracing::Workers::AsyncTransport::DEFAULT_FLUSH_INTERVAL
        )
        # transport and buffers
        @transport = Datadog::CI::TestVisibility::Transport.new(api_key: options.fetch(:api_key))

        @traces_flushed = 0

        # one worker for flushing events
        @worker = nil

        # Once stopped, this writer instance cannot be restarted.
        # This allow for graceful shutdown, while preventing
        # the host application from inadvertently start new
        # threads during shutdown.
        @stopped = false
      end

      # Explicitly starts the {Writer}'s internal worker.
      #
      # The {Writer} is also automatically started when necessary during calls to {.write}.
      def start
        return false if @stopped

        pid = Process.pid
        return if @worker && pid == @pid

        @pid = pid

        start_worker
        true
      end

      # spawns a worker for spans; they share the same transport which is thread-safe
      # @!visibility private
      def start_worker
        @trace_handler = ->(items, transport) { send_spans(items, transport) }
        @worker = Workers::AsyncTransport.new(
          transport: @transport,
          buffer_size: @buff_size,
          on_trace: @trace_handler,
          interval: @flush_interval
        )

        @worker.start
      end

      # Gracefully shuts down this writer.
      #
      # Once stopped methods calls won't fail, but
      # no internal work will be performed.
      #
      # It is not possible to restart a stopped writer instance.
      def stop
        stop_worker
      end

      def stop_worker
        @stopped = true

        return if @worker.nil?

        @worker.stop
        @worker = nil

        true
      end

      private :start_worker, :stop_worker

      # flush spans to the trace-agent, handles spans only
      # @!visibility private
      def send_spans(traces, transport)
        return true if traces.empty?

        # Send traces and get responses
        responses = transport.send_traces(traces)

        # Return if server error occurred.
        !responses.find(&:server_error?)
      end

      # enqueue the trace for submission to the API
      def write(trace)
        start if @worker.nil? || @pid != Process.pid

        worker_local = @worker

        if worker_local
          worker_local.enqueue_trace(trace)
        elsif !@stopped
          Datadog.logger.debug("Writer either failed to start or was stopped before #write could complete")
        end
      end

      # stats returns a dictionary of stats about the writer.
      def stats
        {
          traces_flushed: @traces_flushed,
          transport: @transport.stats
        }
      end

      private

      def reset_stats!
        @traces_flushed = 0
        @transport.stats.reset!
      end
    end
  end
end
