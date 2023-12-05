# frozen_string_literal: true

require_relative "base"
require_relative "../../ext/test"

module Datadog
  module CI
    module TestVisibility
      module Serializers
        class TestSuite < Base
          CONTENT_FIELDS = (["test_session_id", "test_module_id", "test_suite_id"] + Base::CONTENT_FIELDS).freeze

          CONTENT_MAP_SIZE = calculate_content_map_size(CONTENT_FIELDS)

          REQUIRED_FIELDS = (["test_session_id", "test_module_id", "test_suite_id"] + Base::REQUIRED_FIELDS).freeze

          def content_fields
            CONTENT_FIELDS
          end

          def content_map_size
            CONTENT_MAP_SIZE
          end

          def type
            Ext::AppTypes::TYPE_TEST_SUITE
          end

          def name
            "#{@span.get_tag(Ext::Test::TAG_FRAMEWORK)}.test_suite"
          end

          def resource
            "#{@span.get_tag(Ext::Test::TAG_FRAMEWORK)}.test_suite.#{@span.get_tag(Ext::Test::TAG_SUITE)}"
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
