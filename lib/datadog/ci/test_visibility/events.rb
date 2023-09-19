# frozen_string_literal: true

require_relative "events/test"
require_relative "events/span"

module Datadog
  module CI
    module TestVisibility
      module Events
        module_function

        def extract_from_trace(trace)
          # TODO: replace with filter_map when 1.0
          trace.spans.map { |span| convert_span(span) }.reject(&:nil?)
        end

        def convert_span(span)
          case span.type
          when Datadog::CI::Ext::AppTypes::TYPE_TEST
            Events::Test.new(span)
          # TODO move to constant
          when "span"
            Events::Span.new(span)
          end
        end
      end
    end
  end
end
