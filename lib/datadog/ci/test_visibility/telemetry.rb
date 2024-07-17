# frozen_string_literal: true

require_relative "../ext/app_types"
require_relative "../ext/telemetry"
require_relative "../ext/test"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module TestVisibility
      # Telemetry for test visibility
      class Telemetry
        SPAN_TYPE_TO_TELEMETRY_EVENT_TYPE = {
          Ext::AppTypes::TYPE_TEST => Ext::Telemetry::EventType::TEST,
          Ext::AppTypes::TYPE_TEST_SUITE => Ext::Telemetry::EventType::SUITE,
          Ext::AppTypes::TYPE_TEST_MODULE => Ext::Telemetry::EventType::MODULE,
          Ext::AppTypes::TYPE_TEST_SESSION => Ext::Telemetry::EventType::SESSION
        }.freeze

        def event_created(span)
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_EVENT_CREATED, 1, tags_from_span(span))
        end

        def event_finished(span)
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_EVENT_FINISHED, 1, tags_from_span(span))
        end

        private

        def tags_from_span(span)
          {
            Ext::Telemetry::TAG_EVENT_TYPE => SPAN_TYPE_TO_TELEMETRY_EVENT_TYPE.fetch(span.type, "unknown"),
            Ext::Telemetry::TAG_TEST_FRAMEWORK => span.get_tag(Ext::Test::TAG_FRAMEWORK)
          }
        end
      end
    end
  end
end
