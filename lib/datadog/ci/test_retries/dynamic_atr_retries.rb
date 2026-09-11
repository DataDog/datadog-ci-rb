# frozen_string_literal: true

require_relative "../ext/settings"
require_relative "../utils/parsing"

module Datadog
  module CI
    module TestRetries
      # Dynamic Auto Test Retries: duration-based retry budgets instead of a flat per-test limit.
      #
      # When DD_CIVISIBILITY_DYNAMIC_ATR_ENABLED is set, the number of retries for a failing
      # test is determined by the duration of its initial attempt, using the same duration
      # buckets as Early Flake Detection (5s / 10s / 30s / 5m / >5m). The budgets can be
      # overridden with DD_CIVISIBILITY_DYNAMIC_ATR_BUCKETS (five comma-separated integers
      # in [1, 20]); when unset, the EFD slow-test-retry settings from the backend are used.
      module DynamicATRRetries
        BUCKET_COUNT = 5
        MAX_RETRIES_PER_BUCKET = 20

        # @return [Boolean] whether duration-based ATR retry budgets are enabled
        def self.enabled?
          Utils::Parsing.convert_to_bool(ENV[Ext::Settings::ENV_DYNAMIC_ATR_ENABLED])
        end

        # @return [Array<Integer>?, nil] configured ATR retry buckets, or nil to use the EFD retry settings
        def self.buckets
          raw = ENV[Ext::Settings::ENV_DYNAMIC_ATR_BUCKETS]
          return nil if raw.nil? || raw.empty?

          begin
            parsed = raw.split(",").map { |v| Integer(v.strip) }
          rescue ArgumentError
            parsed = []
          end

          if parsed.length != BUCKET_COUNT || parsed.any? { |v| v < 1 || v > MAX_RETRIES_PER_BUCKET }
            Datadog.logger.warn(
              "Invalid #{Ext::Settings::ENV_DYNAMIC_ATR_BUCKETS} value '#{raw}'; " \
                "expected five comma-separated integers in [1, #{MAX_RETRIES_PER_BUCKET}]"
            )
            return nil
          end

          parsed
        end
      end
    end
  end
end
