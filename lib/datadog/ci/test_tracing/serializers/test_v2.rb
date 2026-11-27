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

          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new
            # @type var packer: untyped

            corr_id = itr_correlation_id
            packer.write_map_header(3)

            packer.write("type")
            packer.write(Ext::AppTypes::TYPE_TEST)
            packer.write("version")
            packer.write(2)

            packer.write("content")
            packer.write_map_header(corr_id.nil? ? CONTENT_MAP_SIZE : CONTENT_MAP_SIZE_WITH_ITR_CORRELATION_ID)

            packer.write("test_session_id")
            packer.write(test_session_id)
            packer.write("test_module_id")
            packer.write(test_module_id)
            packer.write("test_suite_id")
            packer.write(test_suite_id)
            packer.write("trace_id")
            packer.write(trace_id)
            packer.write("span_id")
            packer.write(span_id)
            packer.write("name")
            packer.write(name)
            packer.write("resource")
            packer.write(resource)
            packer.write("service")
            packer.write(service)
            packer.write("error")
            packer.write(error)
            packer.write("start")
            packer.write(start)
            packer.write("duration")
            packer.write(duration)
            packer.write("meta")
            packer.write(@meta)
            packer.write("metrics")
            packer.write(metrics)
            packer.write("type")
            packer.write(span_type)

            unless corr_id.nil?
              packer.write("itr_correlation_id")
              packer.write(corr_id)
            end

            packer
          end

          def version
            2
          end

          def event_type
            Ext::AppTypes::TYPE_TEST
          end

          def name
            @name ||= "#{@span.get_tag(Ext::Test::TAG_FRAMEWORK)}.test"
          end

          def resource
            @resource ||= "#{@span.get_tag(Ext::Test::TAG_SUITE)}.#{@span.get_tag(Ext::Test::TAG_NAME)}"
          end

          def itr_correlation_id
            options[:itr_correlation_id]
          end

          private

          def validate_required_fields!
            add_error("test_session_id", "is required") if test_session_id.nil?
            add_error("test_module_id", "is required") if test_module_id.nil?
            add_error("test_suite_id", "is required") if test_suite_id.nil?
            add_error("trace_id", "is required") if trace_id.nil?
            add_error("span_id", "is required") if span_id.nil?
            add_error("error", "is required") if error.nil?
            add_error("name", "is required") if name.nil?
            add_error("resource", "is required") if resource.nil?
          end

          def required_fields
            REQUIRED_FIELDS
          end
        end
      end
    end
  end
end
