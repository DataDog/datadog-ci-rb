# frozen_string_literal: true

require "datadog/tracing/span_operation"

module Datadog
  module CI
    # Represents an ignored span when CI visibility is disabled.
    # Replaces all methods with no-op.
    #
    # @public_api
    class NullSpan < Span
      def initialize
        super(Datadog::Tracing::SpanOperation.new("null.span"))
      end

      def id
      end

      def name
      end

      def service
      end

      def type
      end

      def passed!
      end

      def failed!(exception: nil)
      end

      def skipped!(exception: nil, reason: nil)
      end

      def get_tag(key)
      end

      def set_tag(key, value)
      end

      def set_metric(key, value)
      end

      def finish
      end

      def set_tags(tags)
      end

      def set_environment_runtime_tags
      end

      def set_default_tags
      end

      def set_parameters(arguments, metadata = {})
      end

      def to_s
        self.class.to_s
      end
    end
  end
end
