# frozen_string_literal: true

require_relative "../ext/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module Transport
      module Telemetry
        def self.events_enqueued_for_serialization(count)
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_EVENTS_ENQUEUED, count)
        end

        def self.endpoint_payload_events_count(count, endpoint:)
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_EVENTS_COUNT,
            count.to_f,
            tags(endpoint: endpoint)
          )
        end

        def self.endpoint_payload_serialization_ms(duration_ms, endpoint:)
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_EVENTS_SERIALIZATION_MS,
            duration_ms,
            tags(endpoint: endpoint)
          )
        end

        def self.endpoint_payload_dropped(count, endpoint:)
          Utils::Telemetry.inc(
            Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_DROPPED,
            count,
            tags(endpoint: endpoint)
          )
        end

        def self.endpoint_payload_requests(count, endpoint:, compressed:)
          tags = tags(endpoint: endpoint)
          tags[Ext::Telemetry::TAG_REQUEST_COMPRESSED] = "true" if compressed

          Utils::Telemetry.inc(Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_REQUESTS, count, tags)
        end

        def self.endpoint_payload_requests_ms(duration_ms, endpoint:)
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_REQUESTS_MS,
            duration_ms,
            tags(endpoint: endpoint)
          )
        end

        def self.endpoint_payload_bytes(bytesize, endpoint:)
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_BYTES,
            bytesize.to_f,
            tags(endpoint: endpoint)
          )
        end

        def self.endpoint_payload_requests_errors(count, endpoint:, error_type:, status_code:)
          tags = tags(endpoint: endpoint)

          tags[Ext::Telemetry::TAG_ERROR_TYPE] = error_type if error_type
          tags[Ext::Telemetry::TAG_STATUS_CODE] = status_code.to_s if status_code

          Utils::Telemetry.inc(Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_REQUESTS_ERRORS, count, tags)
        end

        def self.tags(endpoint:)
          {Ext::Telemetry::TAG_ENDPOINT => endpoint}
        end
      end
    end
  end
end
