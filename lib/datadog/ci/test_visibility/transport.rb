# frozen_string_literal: true

require "msgpack"
require "datadog/core/encoding"
require "datadog/core/environment/identity"
# use it to chunk payloads by size
# require "datadog/core/chunker"

require_relative "serializers/factories/test_level"
require_relative "../ext/transport"
require_relative "../transport/http"

module Datadog
  module CI
    module TestVisibility
      class Transport
        def initialize(
          api_key:,
          site: "datadoghq.com",
          serializers_factory: Datadog::CI::TestVisibility::Serializers::Factories::TestLevel
        )
          @serializers_factory = serializers_factory
          @api_key = api_key
          @http = Datadog::CI::Transport::HTTP.new(
            host: "#{Ext::Transport::TEST_VISIBILITY_INTAKE_HOST_PREFIX}.#{site}",
            port: 443
          )
        end

        def send_traces(traces)
          return [] if traces.nil? || traces.empty?

          encoded_events = encode_traces(traces)
          if encoded_events.empty?
            Datadog.logger.debug("[TestVisibility::Transport] empty serializable events list, skipping send")
            return []
          end

          encoded_payload = pack_events(encoded_events)

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

        def encode_traces(traces)
          # TODO: replace map.filter with filter_map when 1.0 is released
          traces.flat_map do |trace|
            trace.spans.map do |span|
              serializer = @serializers_factory.serializer(trace, span)

              if serializer.valid?
                encoder.encode(serializer)
              else
                Datadog.logger.debug { "Invalid span skipped: #{span}" }
                nil
              end
            end.filter { |encoded_event| !encoded_event.nil? }
          end
        end

        def encoder
          Datadog::Core::Encoding::MsgpackEncoder
        end

        def pack_events(encoded_events)
          packer = MessagePack::Packer.new

          packer.write_map_header(3) # Set header with how many elements in the map

          packer.write("version")
          packer.write(1)

          packer.write("metadata")
          packer.write_map_header(1)

          packer.write("*")
          packer.write_map_header(3)

          packer.write("runtime-id")
          packer.write(Datadog::Core::Environment::Identity.id)

          packer.write("language")
          packer.write(Datadog::Core::Environment::Identity.lang)

          packer.write("library_version")
          packer.write(Datadog::CI::VERSION::STRING)

          packer.write("events")
          packer.write_array_header(encoded_events.size)

          (packer.buffer.to_a + encoded_events).join
        end
      end
    end
  end
end
