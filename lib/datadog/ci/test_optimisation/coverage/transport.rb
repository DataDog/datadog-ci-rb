# frozen_string_literal: true

require_relative "event"
require_relative "../../transport/event_platform_transport"

module Datadog
  module CI
    module TestOptimisation
      module Coverage
        class Transport < Datadog::CI::Transport::EventPlatformTransport
          private

          def send_payload(encoded_payload)
            api.citestcov_request(
              path: Ext::Transport::TEST_COVERAGE_INTAKE_PATH,
              payload: encoded_payload
            )
          end

          def encode_events(events)
            events.filter_map do |event|
              next unless event.valid?

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
