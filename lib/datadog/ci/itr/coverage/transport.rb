# frozen_string_literal: true

require "msgpack"

require "datadog/core/encoding"
require "datadog/core/chunker"

require_relative "event"

module Datadog
  module CI
    module ITR
      module Coverage
        class Transport
          DEFAULT_MAX_PAYLOAD_SIZE = 5 * 1024 * 1024

          attr_reader :api,
            :max_payload_size

          def initialize(api:, max_payload_size: DEFAULT_MAX_PAYLOAD_SIZE)
            @api = api
            @max_payload_size = max_payload_size
          end

          def send_events(events)
            return [] if events.nil? || events.empty?

            Datadog.logger.debug { "Sending #{events.count} events..." }

            encoded_events = encode_events(events)
            if encoded_events.empty?
              Datadog.logger.debug { "Empty encoded events list, skipping send" }
              return []
            end

            responses = []

            Datadog::Core::Chunker.chunk_by_size(encoded_events, max_payload_size).map do |chunk|
              encoded_payload = pack_events(chunk)
              Datadog.logger.debug do
                "Send chunk of #{chunk.count} events; payload size #{encoded_payload.size}"
              end

              response = send_payload(encoded_payload)

              responses << response
            end
          end

          private

          def send_payload(encoded_payload)
            api.citestcov_request(
              path: Ext::Transport::TEST_COVERAGE_INTAKE_PATH,
              payload: encoded_payload
            )
          end

          def encoder
            Datadog::Core::Encoding::MsgpackEncoder
          end

          def encode_events(events)
            events.filter_map do |event|
              next unless event.valid?

              encoded = encoder.encode(event)
              if encoded.size > max_payload_size
                # This single event is too large, we can't flush it
                Datadog.logger.warn("Dropping coverage event. Payload too large: '#{event}'")
                Datadog.logger.warn(encoded)

                next
              end

              encoded
            end
          end

          def pack_events(encoded_events)
            packer = MessagePack::Packer.new

            packer.write_map_header(2)
            packer.write("version")
            packer.write(2)

            packer.write("coverages")
            packer.write_array_header(encoded_events.count)

            (packer.buffer.to_a + encoded_events).join
          end
        end
      end
    end
  end
end
