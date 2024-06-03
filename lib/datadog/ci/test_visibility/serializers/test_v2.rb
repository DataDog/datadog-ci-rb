# frozen_string_literal: true

require_relative "test_v1"
require_relative "../../ext/test"

module Datadog
  module CI
    module TestVisibility
      module Serializers
        class TestV2 < TestV1
          CONTENT_FIELDS = (%w[test_session_id test_module_id test_suite_id] + TestV1::CONTENT_FIELDS).freeze

          CONTENT_FIELDS_WITH_ITR_CORRELATION_ID = (CONTENT_FIELDS + %w[itr_correlation_id]).freeze

          CONTENT_MAP_SIZE = calculate_content_map_size(CONTENT_FIELDS)

          CONTENT_MAP_SIZE_WITH_ITR_CORRELATION_ID = calculate_content_map_size(CONTENT_FIELDS_WITH_ITR_CORRELATION_ID)

          REQUIRED_FIELDS = (%w[test_session_id test_module_id test_suite_id] + TestV1::REQUIRED_FIELDS).freeze

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
