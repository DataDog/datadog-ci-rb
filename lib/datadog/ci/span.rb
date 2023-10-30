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
        CI::Recorder.failed!(@current_step_span, exception)
      end

      def skipped!(exception = nil)
        CI::Recorder.skipped!(@current_step_span, exception)
      end
    end
  end
end
