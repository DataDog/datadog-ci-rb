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

        def self.telemetry
          Datadog.send(:components).telemetry
        end
      end
    end
  end
end
