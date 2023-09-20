# frozen_string_literal: true

require_relative "base"
require_relative "../../ext/test"

module Datadog
  module CI
    module TestVisibility
      module Serializer
        class Test < Base
          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new unless defined?(@packer)

            packer.write_map_header(3)

            packer.write("type")
            packer.write("test")

            packer.write("version")
            packer.write(1)

            packer.write("content")

            packer.write_map_header(10)

            packer.write("trace_id")
            packer.write(@trace.id)

            packer.write("span_id")
            packer.write(@span.id)

            packer.write("name")
            packer.write("#{@span.get_tag(Ext::Test::TAG_FRAMEWORK)}.test")

            packer.write("resource")
            packer.write("#{@span.get_tag(Ext::Test::TAG_SUITE)}.#{@span.get_tag(Ext::Test::TAG_NAME)}")

            packer.write("service")
            packer.write(@span.service)

            packer.write("type")
            packer.write("test")

            packer.write("start")
            packer.write(time_nano(@span.start_time))

            packer.write("duration")
            packer.write(duration_nano(@span.duration))

            packer.write("meta")
            packer.write(@span.meta)

            # metrics have the same value as meta
            packer.write("metrics")
            packer.write({})
          end
        end
      end
    end
  end
end
