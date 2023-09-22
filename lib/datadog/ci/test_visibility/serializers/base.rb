# frozen_string_literal: true

module Datadog
  module CI
    module TestVisibility
      module Serializers
        class Base
          attr_reader :trace, :span

          def initialize(trace, span)
            @trace = trace
            @span = span
          end

          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new

            packer.write_map_header(3)

            write_field(packer, "type")
            write_field(packer, "version")

            packer.write("content")
            packer.write_map_header(content_map_size)

            content_fields.each do |field|
              if field.is_a?(Hash)
                field.each do |field_name, method|
                  write_field(packer, field_name, method)
                end
              else
                write_field(packer, field)
              end
            end
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

          def type
          end

          def version
            1
          end

          def span_type
            @span.type
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
            time_nano(@span.start_time)
          end

          def duration
            duration_nano(@span.duration)
          end

          def meta
            @span.meta
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

          def write_field(packer, field_name, method = nil)
            method ||= field_name

            packer.write(field_name)
            packer.write(send(method))
          end

          # Used for serialization
          # @return [Integer] in nanoseconds since Epoch
          def time_nano(time)
            time.to_i * 1000000000 + time.nsec
          end

          # Used for serialization
          # @return [Integer] in nanoseconds since Epoch
          def duration_nano(duration)
            (duration * 1e9).to_i
          end
        end
      end
    end
  end
end
