# frozen_string_literal: true

require "set"

require_relative "../../ext/test"
require_relative "meta_truncation"

module Datadog
  module CI
    module TestTracing
      module Serializers
        class Base
          MINIMUM_TIMESTAMP_NANO = 946684800000000000
          MINIMUM_DURATION_NANO = 0
          MAXIMUM_DURATION_NANO = 9223372036854775807

          EMPTY_ERRORS = {}.freeze
          private_constant :EMPTY_ERRORS

          CONTENT_FIELDS = [
            "name", "resource", "service",
            "error", "start", "duration",
            "meta", "metrics",
            "type" => "span_type"
          ].freeze

          REQUIRED_FIELDS = %w[error name resource start duration].freeze

          attr_reader :trace, :span, :meta, :options

          def initialize(trace, span, options: {})
            @trace = trace
            @span = span
            @options = options

            @meta = prepare_meta(@span.meta)

            @errors = nil
            @validated = false
          end

          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new

            packer.write_map_header(3)

            packer.write("type")
            packer.write(event_type)
            packer.write("version")
            packer.write(version)

            packer.write("content")
            packer.write_map_header(content_map_size)

            content_fields.each do |field|
              if field.is_a?(Hash)
                field.each do |field_name, method|
                  packer.write(field_name)
                  packer.write(send(method))
                end
              else
                packer.write(field)
                packer.write(send(field))
              end
            end
          end

          # validates according to citestcycle json schema
          def valid?
            validate! unless @validated

            errors = @errors
            errors.nil? || errors.empty?
          end

          def validate!
            @errors&.clear

            validate_required_fields!
            validate_start_time!
            validate_duration!

            @validated = true
          end

          def validation_errors
            @errors || EMPTY_ERRORS
          end

          def content_fields
            []
          end

          def content_map_size
            0
          end

          def runtime_id
            @trace.runtime_id
          end

          def trace_id
            @trace.id
          end

          def span_id
            @span.id
          end

          def parent_id
            @span.parent_id
          end

          def test_session_id
            return @test_session_id if defined?(@test_session_id)

            @test_session_id = to_integer(@span.get_tag(Ext::Test::TAG_TEST_SESSION_ID))
          end

          def test_module_id
            return @test_module_id if defined?(@test_module_id)

            @test_module_id = to_integer(@span.get_tag(Ext::Test::TAG_TEST_MODULE_ID))
          end

          def test_suite_id
            return @test_suite_id if defined?(@test_suite_id)

            @test_suite_id = to_integer(@span.get_tag(Ext::Test::TAG_TEST_SUITE_ID))
          end

          def version
            1
          end

          def span_type
            @span.type
          end

          def event_type
            "span"
          end

          def name
            @span.name
          end

          def resource
            @span.resource
          end

          def service
            @span.service
          end

          def start
            @start ||= time_nano(@span.start_time)
          end

          def duration
            @duration ||= duration_nano(@span.duration)
          end

          def metrics
            @span.metrics
          end

          def error
            @span.status
          end

          def self.calculate_content_map_size(fields_list)
            fields_list.reduce(0) do |size, field|
              if field.is_a?(Hash)
                size + field.size
              else
                size + 1
              end
            end
          end

          private

          def prepare_meta(raw_meta)
            has_transient = raw_meta.key?(Ext::Test::TAG_TEST_SESSION_ID) ||
              raw_meta.key?(Ext::Test::TAG_TEST_MODULE_ID) ||
              raw_meta.key?(Ext::Test::TAG_TEST_SUITE_ID)

            needs_truncation = false
            raw_meta.each_value do |value|
              if value.is_a?(String) && value.bytesize > MetaTruncation::MAX_META_STRING_LENGTH &&
                  value.length > MetaTruncation::MAX_META_STRING_LENGTH
                needs_truncation = true
                break
              end
            end

            return raw_meta unless has_transient || needs_truncation

            filtered = raw_meta.dup
            if has_transient
              filtered.delete(Ext::Test::TAG_TEST_SESSION_ID)
              filtered.delete(Ext::Test::TAG_TEST_MODULE_ID)
              filtered.delete(Ext::Test::TAG_TEST_SUITE_ID)
            end

            if needs_truncation
              filtered.each do |key, value|
                if value.is_a?(String) && value.bytesize > MetaTruncation::MAX_META_STRING_LENGTH &&
                    value.length > MetaTruncation::MAX_META_STRING_LENGTH
                  filtered[key] = value[0, MetaTruncation::MAX_META_STRING_LENGTH]
                end
              end
            end

            filtered
          end

          def validate_start_time!
            start_value = start
            if start_value.nil?
              add_error("start", "is required")
            elsif start_value < MINIMUM_TIMESTAMP_NANO
              add_error("start", "must be greater than or equal to #{MINIMUM_TIMESTAMP_NANO}")
            end
          end

          def validate_duration!
            duration_value = duration
            if duration_value.nil?
              add_error("duration", "is required")
            else
              if duration_value < MINIMUM_DURATION_NANO
                add_error("duration", "must be greater than or equal to #{MINIMUM_DURATION_NANO}")
              end
              if duration_value > MAXIMUM_DURATION_NANO
                add_error("duration", "must be less than or equal to #{MAXIMUM_DURATION_NANO}")
              end
            end
          end

          def validate_required_fields!
            required_fields.each do |field|
              validate_required!(field)
            end
          end

          def validate_required!(field)
            if send(field).nil?
              add_error(field, "is required")
            end
          end

          def validate_greater_than_or_equal!(field, value)
            field_value = send(field)
            return if field_value.nil?

            if field_value < value
              add_error(field, "must be greater than or equal to #{value}")
            end
          end

          def validate_less_than_or_equal!(field, value)
            field_value = send(field)
            return if field_value.nil?

            if field_value > value
              add_error(field, "must be less than or equal to #{value}")
            end
          end

          def add_error(field, message)
            errors = (@errors ||= {})
            (errors[field] ||= Set.new) << message
          end

          def required_fields
            []
          end

          def write_field(packer, field_name, method = nil)
            method ||= field_name

            packer.write(field_name)
            packer.write(send(method))
          end

          # in nanoseconds since Epoch
          def time_nano(time)
            time.to_i * 1000000000 + time.nsec
          end

          # in nanoseconds
          def duration_nano(duration)
            (duration * 1e9).to_i
          end

          def to_s
            "#{self.class.name}(id:#{span_id},name:#{name})"
          end

          def to_integer(value)
            value&.to_i
          end

          def test_tracing
            @test_tracing ||= Datadog::CI.send(:test_tracing)
          end
        end
      end
    end
  end
end
