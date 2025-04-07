# frozen_string_literal: true

require "json"

require "datadog/core/chunker"

module Datadog
  module CI
    module Logs
      class Transport
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

          encoded_events = events.filter_map do |event|
            encoded_event = event.to_json
            if event_too_large?(event, encoded_event)
              next
            end

            encoded_event
          end

          responses = []
          Datadog::Core::Chunker.chunk_by_size(encoded_events, max_payload_size).map do |chunk|
            encoded_payload = pack_events(chunk)
            Datadog.logger.debug do
              "[#{self.class.name}] Send chunk of #{chunk.count} events; payload size #{encoded_payload.size}"
            end

            response = send_payload(encoded_payload)

            responses << response
          end

          responses
        end

        private

        def pack_events(encoded_events)
          "[#{encoded_events.join(",")}]"
        end

        def event_too_large?(event, encoded_event)
          return false unless encoded_event.size > max_payload_size

          # This single event is too large, we can't flush it
          Datadog.logger.debug(
            "[#{self.class.name}] Dropping event for logs intake. Payload too large: '#{event.inspect}'"
          )

          true
        end

        def send_payload(encoded_payload)
          @api.logs_intake_request(path: "/v1/input", payload: encoded_payload)
        end
      end
    end
  end
end
