# frozen_string_literal: true

require_relative "test_v1"
require_relative "../../ext/test"

module Datadog
  module CI
    module TestVisibility
      module Serializers
        class TestV2 < TestV1
          CONTENT_FIELDS = [
            "trace_id", "span_id",
            "name", "resource", "service",
            "error", "start", "duration",
            "meta", "metrics", "test_session_id",
            "type" => "span_type"
          ].freeze

          CONTENT_MAP_SIZE = calculate_content_map_size(CONTENT_FIELDS)

          REQUIRED_FIELDS = [
            "test_session_id",
            "trace_id",
            "span_id",
            "error",
            "name",
            "resource",
            "start",
            "duration"
          ].freeze

          def content_fields
            CONTENT_FIELDS
          end

          def content_map_size
            CONTENT_MAP_SIZE
          end

          def version
            2
          end

          private

          def required_fields
            REQUIRED_FIELDS
          end
        end
      end
    end
  end
end
