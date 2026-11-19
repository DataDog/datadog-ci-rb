# frozen_string_literal: true

require "securerandom"
require_relative "utils/identity"
require_relative "event_span"
require_relative "event_trace"

module Datadog
  module CI
    # Tracks CI events without using the application tracer's context or lifecycle.
    class EventTracer
      attr_reader :writer

      def initialize(writer:, service: nil, tags: {})
        @writer = writer
        @service = service
        @tags = tags
        @context_key = :"datadog_ci_events_#{object_id}"
      end

      def trace(name, service: nil, type: nil, resource: nil, new_trace: false, tags: {})
        parent = active_span unless new_trace
        trace_id = parent ? parent.trace_id : SecureRandom.random_number((1 << 63) - 1) + 1
        context = stack
        span = EventSpan.new(
          name,
          trace_id: trace_id,
          parent_id: parent ? parent.id : 0,
          service: service || parent&.service || @service,
          type: type,
          resource: resource,
          tags: @tags.merge(tags)
        ) { |finished| finish_span(finished, context) }
        span.set_metric("_dd.top_level", 1) if !parent || parent.service != span.service
        context << span
        return span unless block_given?

        begin
          yield span, active_trace
        rescue => error
          span.set_error(error)
          raise
        ensure
          span.finish
        end
      end

      def active_span
        stack.reverse_each.find { |span| !span.finished? }
      end

      def active_trace
        span = active_span
        EventTrace.new(span.trace_id, [], runtime_id: runtime_id) if span
      end

      def shutdown!
        @writer.shutdown!
      end

      private

      def stack
        Thread.current[@context_key] ||= []
      end

      def runtime_id
        Utils::Identity.id
      end

      def finish_span(span, context)
        context.delete(span)
        @writer.write(EventTrace.new(span.trace_id, [span], runtime_id: runtime_id))
      end
    end
  end
end
