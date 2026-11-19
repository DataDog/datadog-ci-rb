# frozen_string_literal: true

module Datadog
  module CI
    module Telemetry
      # Keeps telemetry calls inert when collection is disabled.
      class NullComponent
        def enabled?
          false
        end

        alias_method :enabled, :enabled?

        def inc(namespace, metric_name, value, tags: {}, common: true)
        end

        def distribution(namespace, metric_name, value, tags: {}, common: true)
        end

        def flush
        end

        def disable!
        end

        def shutdown!
        end
      end
    end
  end
end
