# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module Time
        WALL_CLOCK = ::Time.method(:now)
        MONOTONIC_CLOCK = ::Process.method(:clock_gettime)

        def self.now
          return ::Time.now_without_mock_time if ::Time.respond_to?(:now_without_mock_time)

          WALL_CLOCK.call
        end

        def self.get_time(unit = :float_second)
          if ::Process.respond_to?(:clock_gettime_without_mock)
            ::Process.clock_gettime_without_mock(::Process::CLOCK_MONOTONIC, unit).to_f
          else
            MONOTONIC_CLOCK.call(::Process::CLOCK_MONOTONIC, unit).to_f
          end
        end

        def self.measure(unit = :float_second)
          started_at = get_time(unit)
          yield
          get_time(unit) - started_at
        end
      end
    end
  end
end
