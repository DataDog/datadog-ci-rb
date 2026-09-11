# frozen_string_literal: true

require_relative "../ext/telemetry"

module Datadog
  module CI
    module Utils
      module Telemetry
        def self.inc(metric_name, count, tags = {})
          telemetry.inc(Ext::Telemetry::NAMESPACE, metric_name, count, tags: tags)
        end

        def self.distribution(metric_name, value, tags = {})
          telemetry.distribution(Ext::Telemetry::NAMESPACE, metric_name, value, tags: tags)
        end

        def self.itr_forced_run
          inc(Ext::Telemetry::METRIC_ITR_FORCED_RUN, 1, itr_test_tags)
        end

        def self.itr_unskippable
          inc(Ext::Telemetry::METRIC_ITR_UNSKIPPABLE, 1, itr_test_tags)
        end

        def self.record_dynamic_atr_retries(has_custom_buckets:)
          tags = has_custom_buckets ? {Ext::Telemetry::TAG_HAS_CUSTOM_BUCKETS => "true"} : {}
          inc(Ext::Telemetry::METRIC_DYNAMIC_ATR_RETRIES_ENABLED, 1, tags)
        end

        def self.telemetry
          Datadog.send(:components).telemetry
        end

        def self.itr_test_tags
          {
            Ext::Telemetry::TAG_EVENT_TYPE => Ext::Telemetry::EventType::TEST
          }
        end
        private_class_method :itr_test_tags
      end
    end
  end
end
