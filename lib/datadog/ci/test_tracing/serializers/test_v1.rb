# frozen_string_literal: true

require_relative "base"
require_relative "../../ext/test"

module Datadog
  module CI
    module TestTracing
      module Serializers
        class TestV1 < Base
          CONTENT_FIELDS = (%w[trace_id span_id] + Base::CONTENT_FIELDS).freeze

          CONTENT_MAP_SIZE = calculate_content_map_size(CONTENT_FIELDS)

          REQUIRED_FIELDS = (%w[trace_id span_id] + Base::REQUIRED_FIELDS).freeze

          def content_fields
            CONTENT_FIELDS
          end

          def content_map_size
            CONTENT_MAP_SIZE
          end

          def event_type
            Ext::AppTypes::TYPE_TEST
          end

          def name
            "#{@span.get_tag(Ext::Test::TAG_FRAMEWORK)}.test"
          end

          def resource
            "#{@span.get_tag(Ext::Test::TAG_SUITE)}.#{@span.get_tag(Ext::Test::TAG_NAME)}"
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
