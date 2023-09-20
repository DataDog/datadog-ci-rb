# frozen_string_literal: true

require_relative "serializer/test"
require_relative "serializer/span"

module Datadog
  module CI
    module TestVisibility
      module SomethingThatConvertsTraces
        module_function

        def convert(trace)
          trace.spans.map { |span| convert_span(trace, span) }
        end

        def convert_span(trace, span)
          case span.type
          when Datadog::CI::Ext::AppTypes::TYPE_TEST
            Serializer::Test.new(trace, span)
          else
            Serializer::Span.new(trace, span)
          end
        end
      end
    end
  end
end
