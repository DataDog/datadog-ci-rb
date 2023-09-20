# frozen_string_literal: true

require_relative "something_that_converts_traces"
require "datadog/core/encoding"
# use it to chunk payloads by size
# require "datadog/core/chunker"

module Datadog
  module CI
    module TestVisibility
      class Transport
        def initialize
          @encoder = Datadog::Core::Encoding::MsgpackEncoder
        end

        def send_traces(traces)
          # convert traces to events and construct payload
          events = traces.flat_map { |trace| SomethingThatConvertsTraces.convert(trace) }
          payload = Payload.new(events)
          # @encoder.encode(payload)
        end

        private

        # represents payload with some subset of serializable events to be sent to CI-APP intake
        class Payload
          def initialize(events)
            @events = events
          end

          def to_msgpack(packer)
            packer ||= MessagePack::Packer.new

            packer.write_map_header(3) # Set header with how many elements in the map
            packer.write("version")
            packer.write(1)

            packer.write("metadata")
            packer.write_map_header(3)

            packer.write("runtime-id")
            packer.write(@events.first.runtime_id)

            packer.write("language")
            packer.write("ruby")

            packer.write("library_version")
            packer.write(Datadog::CI::VERSION::STRING)

            packer.write_array_header(@events.size)
            packer.write(@events)
          end
        end
      end
    end
  end
end
