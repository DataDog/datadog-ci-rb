# frozen_string_literal: true

module Datadog
  # Public API for Datadog CI visibility
  module CI
    class Span
      attr_reader :tracer_span

      def initialize(tracer_span)
        @tracer_span = tracer_span
      end

      def passed!
        CI::Recorder.passed!(@tracer_span)
      end

      def failed!(exception = nil)
        CI::Recorder.failed!(@tracer_span, exception)
      end

      def skipped!(exception = nil, reason = nil)
        CI::Recorder.skipped!(@tracer_span, exception, reason)
      end

      def finish
        tracer_span.finish
      end
    end
  end
end
