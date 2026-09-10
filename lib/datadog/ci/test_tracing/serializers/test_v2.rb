# frozen_string_literal: true

require_relative "base"
require_relative "../../ext/test"

module Datadog
  module CI
    module TestTracing
      module Serializers
        class TestV2 < Base
          CONTENT_FIELDS = (%w[test_session_id test_module_id test_suite_id trace_id span_id] + Base::CONTENT_FIELDS).freeze

          CONTENT_FIELDS_WITH_ITR_CORRELATION_ID = (CONTENT_FIELDS + %w[itr_correlation_id]).freeze

          CONTENT_MAP_SIZE = calculate_content_map_size(CONTENT_FIELDS)

          CONTENT_MAP_SIZE_WITH_ITR_CORRELATION_ID = calculate_content_map_size(CONTENT_FIELDS_WITH_ITR_CORRELATION_ID)

          REQUIRED_FIELDS = (%w[test_session_id test_module_id test_suite_id trace_id span_id] + Base::REQUIRED_FIELDS).freeze

          def content_fields
            return CONTENT_FIELDS if itr_correlation_id.nil?

            CONTENT_FIELDS_WITH_ITR_CORRELATION_ID
          end

          def content_map_size
            return CONTENT_MAP_SIZE if itr_correlation_id.nil?

            CONTENT_MAP_SIZE_WITH_ITR_CORRELATION_ID
          end

          def version
            2
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

          def itr_correlation_id
            options[:itr_correlation_id]
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
