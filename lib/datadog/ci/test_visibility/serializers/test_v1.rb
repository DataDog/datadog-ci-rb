# frozen_string_literal: true

require_relative "base"
require_relative "../../ext/test"

module Datadog
  module CI
    module TestVisibility
      module Serializers
        class TestV1 < Base
          def content_fields
            @content_fields ||= [
              "trace_id", "span_id", "name", "resource", "service",
              "start", "duration", "meta", "metrics", "error",
              "type" => "span_type"
            ]
          end

          def type
            "test"
          end

          def name
            "#{@span.get_tag(Ext::Test::TAG_FRAMEWORK)}.test"
          end

          def resource
            "#{@span.get_tag(Ext::Test::TAG_SUITE)}.#{@span.get_tag(Ext::Test::TAG_NAME)}"
          end
        end
      end
    end
  end
end
