# frozen_string_literal: true

require "msgpack"
require "datadog/core/encoding"
# use it to chunk payloads by size
# require "datadog/core/chunker"

require_relative "serializers"
require_relative "../ext/transport"
require_relative "../transport/http"

module Datadog
  module CI
    module TestVisibility
      class Transport
        # TODO: rename Serializers module
        def initialize(api_key:, site: "datadoghq.com", serializer: Datadog::CI::TestVisibility::Serializers)
          @serializer = serializer
          @api_key = api_key
          @http = Datadog::CI::Transport::HTTP.new(
            host: "#{Ext::Transport::TEST_VISIBILITY_INTAKE_HOST_PREFIX}.#{site}",
            port: 443
          )
        end

        def send_traces(traces)
          # convert traces to events and construct payload
          # TODO: encode events immediately?
          events = traces.flat_map { |trace| @serializer.convert_trace_to_serializable_events(trace) }

          # move this to validation
          events = events.filter { |event| event.start >= 946684800000000000 && event.duration > 0 }

          payload = Payload.new(events)

          encoded_payload = encoder.encode(payload)

          response = @http.request(
            path: Datadog::CI::Ext::Transport::TEST_VISIBILITY_INTAKE_PATH,
            payload: encoded_payload,
            headers: {
              Ext::Transport::HEADER_DD_API_KEY => @api_key,
              Ext::Transport::HEADER_CONTENT_TYPE => Ext::Transport::CONTENT_TYPE_MESSAGEPACK
            }
          )

          # Tracing writers expect an array of responses
          [response]
        end

        private

        def encoder
          Datadog::Core::Encoding::MsgpackEncoder
        end

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
            packer.write_map_header(1)

            packer.write("*")
            packer.write_map_header(3)

            # TODO: implement our own identity?
            first_event = @events.first
            if first_event
              packer.write("runtime-id")
              packer.write(first_event.runtime_id)
            end

            packer.write("language")
            packer.write("ruby")

            packer.write("library_version")
            packer.write(Datadog::CI::VERSION::STRING)

            packer.write("events")
            packer.write(@events)
          end
        end
      end
    end
  end
end
