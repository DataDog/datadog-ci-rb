# frozen_string_literal: true

require_relative "event"
require_relative "../../ext/telemetry"
require_relative "../../transport/event_platform_transport"
require_relative "../../transport/telemetry"

module Datadog
  module CI
    module TestOptimisation
      module Coverage
        class Transport < Datadog::CI::Transport::EventPlatformTransport
          private

          def telemetry_endpoint_tag
            Ext::Telemetry::Endpoint::CODE_COVERAGE
          end

          def send_payload(encoded_payload)
            api.citestcov_request(
              path: Ext::Transport::TEST_COVERAGE_INTAKE_PATH,
              payload: encoded_payload
            )
          end

          def encode_events(events)
            events.filter_map do |event|
              unless event.valid?
                CI::Transport::Telemetry.endpoint_payload_dropped(1, endpoint: telemetry_endpoint_tag)
                next
              end

              encoded = encoder.encode(event)
              next if event_too_large?(event, encoded)

              encoded
            end
          end

          def write_payload_header(packer)
            packer.write_map_header(2)
            packer.write("version")
            packer.write(2)

            packer.write("coverages")
          end
        end
      end
    end
  end
end
