# frozen_string_literal: true

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
          events = traces.map { |trace| PayloadEvents.convert_from_trace(trace) }
          # payload = Payload.new(events)
          # @encoder.encode(payload)
        end

        private

        # represents payload with some subset of serializable events to be sent to CI-APP intake
        class Payload
          def initialize(events)
          end

          def to_msgpack
          end
        end
      end
    end
  end
end
