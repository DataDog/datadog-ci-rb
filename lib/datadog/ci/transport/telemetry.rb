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
      end
    end
  end
end
