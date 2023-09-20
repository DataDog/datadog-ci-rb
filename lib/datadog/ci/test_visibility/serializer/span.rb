# frozen_string_literal: true

require_relative "base"

module Datadog
  module CI
    module TestVisibility
      module Serializer
        class Span < Base
          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new

            packer.write_map_header(3)

            packer.write("type")
            packer.write("span")

            packer.write("version")
            packer.write(1)

            packer.write("content")

            packer.write_map_header(12)

            packer.write("trace_id")
            packer.write(@trace.id)

            packer.write("span_id")
            packer.write(@span.id)

            packer.write("parent_id")
            packer.write(@span.parent_id)

            packer.write("name")
            packer.write(@span.name)

            packer.write("resource")
            packer.write(@span.resource)

            packer.write("service")
            packer.write(@span.service)

            packer.write("type")
            packer.write(@span.type)

            packer.write("error")
            packer.write(@span.status)

            packer.write("start")
            packer.write(time_nano(@span.start_time))

            packer.write("duration")
            packer.write(duration_nano(@span.duration))

            packer.write("meta")
            packer.write(@span.meta)

            packer.write("metrics")
            packer.write(@span.metrics)
          end
        end
      end
    end
  end
end
