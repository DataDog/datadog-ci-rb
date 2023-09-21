# frozen_string_literal: true

require_relative "base"

module Datadog
  module CI
    module TestVisibility
      module Serializers
        class Span < Base
          def content_fields
            @content_fields ||= [
              "trace_id", "span_id", "parent_id",
              "name", "resource", "service",
              "error", "start", "duration",
              "meta", "metrics",
              "type" => "span_type"
            ]
          end

          def type
            "span"
          end
        end
      end
    end
  end
end
