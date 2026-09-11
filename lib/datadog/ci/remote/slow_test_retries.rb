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

        # Return the EFD retry-bucket index for an initial test duration.
        # Uses the same boundaries as the dynamic ATR feature: <=5->0, <=10->1,
        # <=30->2, <=300->3, >300->4.
        # @param duration [Float] initial attempt duration in seconds
        # @return [Integer] bucket index 0..4
        def retry_bucket_index_for_duration(duration)
          if duration <= 5
            0
          elsif duration <= 10
            1
          elsif duration <= 30
            2
          elsif duration <= 300
            3
          else
            4
          end
        end

        # Return the configured retry budget for an initial test duration.
        # Equivalent to max_attempts_for_duration but uses the bucket index helper.
        # @param duration [Float] initial attempt duration in seconds
        # @return [Integer] retry budget
        def retries_for_duration(duration)
          index = retry_bucket_index_for_duration(duration)
          values = efd_bucket_values
          values[index]
        end

        # Return the 5-element bucket values array.
        # @return [Array<Integer>] 5-element array of retry counts for 5s/10s/30s/5m/>5m buckets
        def efd_bucket_values
          boundaries = [5.0, 10.0, 30.0, 300.0]
          values = Array.new(5, 0)

          boundaries.each_with_index do |boundary, index|
            entry = @entries.find { |e| e.duration == boundary }
            values[index] = entry ? entry.max_attempts : 0
          end

          values
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
