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
          Utils::Telemetry.inc(
            Ext::Telemetry::METRIC_ENDPOINT_PAYLOAD_REQUESTS,
            count,
            tags(endpoint: endpoint, request_compressed: compressed)
          )
        end

        def self.tags(endpoint:, request_compressed: false)
          # @type var tags: Hash[String, String]
          tags = {Ext::Telemetry::TAG_ENDPOINT => endpoint}

          tags[Ext::Telemetry::TAG_REQUEST_COMPRESSED] = "true" if request_compressed

          tags
        end
      end
    end
  end
end
