# frozen_string_literal: true

require "msgpack"

require "datadog/core/encoding"
require "datadog/core/chunker"
require "datadog/core/utils/time"

require_relative "telemetry"

module Datadog
  module CI
    module Transport
      class EventPlatformTransport
        DEFAULT_MAX_PAYLOAD_SIZE = 5 * 1024 * 1024

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

          Telemetry.endpoint_payload_serialization_ms(serialization_duration_ms, telemetry_endpoint_tag)
          Telemetry.events_enqueued_for_serialization(encoded_events.count)

          responses = []

          Datadog::Core::Chunker.chunk_by_size(encoded_events, max_payload_size).map do |chunk|
            encoded_payload = pack_events(chunk)
            Datadog.logger.debug do
              "[#{self.class.name}] Send chunk of #{chunk.count} events; payload size #{encoded_payload.size}"
            end
            Telemetry.endpoint_payload_events_count(chunk.count, telemetry_endpoint_tag)

            response = send_payload(encoded_payload)

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
          Datadog.logger.warn("[#{self.class.name}] Dropping coverage event. Payload too large: '#{event.inspect}'")
          Datadog.logger.warn(encoded_event)

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
