# frozen_string_literal: true

module Datadog
  module CI
    module Remote
      # Parses "slow_test_retries" payload for early flake detection settings
      #
      # Example payload:
      # {
      #  "5s" => 10,
      #  "10s" => 5,
      #  "30s" => 3,
      #  "5m" => 2
      # }
      #
      # The payload above means that for tests that run less than 5 seconds, we should retry them 10 times,
      # for tests that run less than 10 seconds, we should retry them 5 times, and so on.
      class SlowTestRetries
        attr_reader :entries

        Entry = Struct.new(:duration, :max_attempts)

        DURATION_MEASURES = {
          "s" => 1,
          "m" => 60
        }.freeze

        def initialize(payload)
          @entries = parse(payload)
        end

        def max_attempts_for_duration(duration)
          @entries.each do |entry|
            return entry.max_attempts if duration < entry.duration
          end

          0
        end

        private

        def parse(payload)
          (payload || {}).keys.filter_map do |key|
            duration, measure = key.match(/(\d+)(\w+)/)&.captures
            next if duration.nil? || measure.nil? || !DURATION_MEASURES.key?(measure)

            Entry.new(duration.to_f * DURATION_MEASURES.fetch(measure, 1), payload[key].to_i)
          end.sort_by(&:duration)
        end
      end
    end
  end
end
