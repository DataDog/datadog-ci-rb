# frozen_string_literal: true

require "msgpack"

require "datadog/core/encoding"
require "datadog/core/chunker"

require_relative "telemetry"

module Datadog
  module CI
    module Transport
      class EventPlatformTransport
        DEFAULT_MAX_PAYLOAD_SIZE = 4.5 * 1024 * 1024

        attr_reader :api,
          :max_payload_size

        def initialize(api:, max_payload_size: DEFAULT_MAX_PAYLOAD_SIZE)
          @api = api
          @max_payload_size = max_payload_size
        end

        def send_events(events)
          return [] if events.nil? || events.empty?

          Datadog.logger.debug { "[#{self.class.name}] Sending #{events.count} events..." }

          encoded_events = []
          # @type var serialization_duration_ms: Float
          serialization_duration_ms = Core::Utils::Time.measure(:float_millisecond) do
            encoded_events = encode_events(events)
            if encoded_events.empty?
              Datadog.logger.debug { "[#{self.class.name}] Empty encoded events list, skipping send" }
              return []
            end
          end

          Telemetry.events_enqueued_for_serialization(encoded_events.count)
          Telemetry.endpoint_payload_serialization_ms(serialization_duration_ms, endpoint: telemetry_endpoint_tag)

          responses = []

          Datadog::Core::Chunker.chunk_by_size(encoded_events, max_payload_size).map do |chunk|
            encoded_payload = pack_events(chunk)
            Datadog.logger.debug do
              "[#{self.class.name}] Send chunk of #{chunk.count} events; payload size #{encoded_payload.size}"
            end
            Telemetry.endpoint_payload_events_count(chunk.count, endpoint: telemetry_endpoint_tag)

            response = send_payload(encoded_payload)

            Telemetry.endpoint_payload_requests(
              1,
              endpoint: telemetry_endpoint_tag, compressed: response.request_compressed
            )
            Telemetry.endpoint_payload_requests_ms(response.duration_ms, endpoint: telemetry_endpoint_tag)
            Telemetry.endpoint_payload_bytes(response.request_size, endpoint: telemetry_endpoint_tag)

            # HTTP layer could send events and exhausted retries (if any)
            unless response.ok?
              Telemetry.endpoint_payload_dropped(chunk.count, endpoint: telemetry_endpoint_tag)
              Telemetry.endpoint_payload_requests_errors(
                1,
                endpoint: telemetry_endpoint_tag,
                error_type: response.telemetry_error_type,
                status_code: response.code
              )
            end

            responses << response
          end

          responses
        end

        private

        def telemetry_endpoint_tag
          raise NotImplementedError, "must be implemented by the subclass"
        end

        def encoder
          Datadog::Core::Encoding::MsgpackEncoder
        end

        def pack_events(encoded_events)
          packer = MessagePack::Packer.new

          write_payload_header(packer)

          packer.write_array_header(encoded_events.count)
          (packer.buffer.to_a + encoded_events).join
        end

        def event_too_large?(event, encoded_event)
          return false unless encoded_event.size > max_payload_size

          # This single event is too large, we can't flush it
          Datadog.logger.warn(
            "[#{self.class.name}] Dropping test visibility event for endpoint [#{telemetry_endpoint_tag}]. " \
            "Payload too large: '#{event.inspect}'"
          )
          Datadog.logger.warn(encoded_event)

          Telemetry.endpoint_payload_dropped(1, endpoint: telemetry_endpoint_tag)

          true
        end

        def send_payload(encoded_payload)
          raise NotImplementedError
        end

        def encode_events(events)
          raise NotImplementedError
        end

        def write_payload_header(packer)
          raise NotImplementedError
        end
      end
    end
  end
end
