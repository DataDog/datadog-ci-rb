# frozen_string_literal: true

require_relative "base"
require_relative "../../ext/test"

module Datadog
  module CI
    module TestVisibility
      module Serializers
        class TestModule < Base
          CONTENT_FIELDS = (%w[test_session_id test_module_id] + Base::CONTENT_FIELDS).freeze

          CONTENT_MAP_SIZE = calculate_content_map_size(CONTENT_FIELDS)

          REQUIRED_FIELDS = (%w[test_session_id test_module_id] + Base::REQUIRED_FIELDS).freeze

          def content_fields
            CONTENT_FIELDS
          end

          def content_map_size
            CONTENT_MAP_SIZE
          end

          def event_type
            Ext::AppTypes::TYPE_TEST_MODULE
          end

          def name
            "#{@span.get_tag(Ext::Test::TAG_FRAMEWORK)}.test_module"
          end

          def resource
            "#{@span.get_tag(Ext::Test::TAG_FRAMEWORK)}.test_module.#{@span.get_tag(Ext::Test::TAG_MODULE)}"
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
