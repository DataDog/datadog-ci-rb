# frozen_string_literal: true

require_relative "serializers/test_v1"
require_relative "serializers/span"

module Datadog
  module CI
    module TestVisibility
      module Serializers
        module_function

        def convert_trace_to_serializable_events(trace)
          trace.spans.map { |span| convert_span_to_serializable_event(trace, span) }
        end

        # for test suite visibility we might need to make it configurable
        def convert_span_to_serializable_event(trace, span)
          case span.type
          when Datadog::CI::Ext::AppTypes::TYPE_TEST
            Serializers::TestV1.new(trace, span)
          else
            Serializers::Span.new(trace, span)
          end
        end
      end
    end
  end
end
