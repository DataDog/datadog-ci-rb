# frozen_string_literal: true

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
          end
        end
      end
    end
  end
end
