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
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::PASS)
      end

      def failed!(exception = nil)
        tracer_span.status = 1
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::FAIL)
        tracer_span.set_error(exception) unless exception.nil?
      end

      def skipped!(exception = nil, reason = nil)
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::SKIP)
        tracer_span.set_error(exception) unless exception.nil?
        tracer_span.set_tag(CI::Ext::Test::TAG_SKIP_REASON, reason) unless reason.nil?
      end

      def finish
        tracer_span.finish
      end
    end
  end
end
