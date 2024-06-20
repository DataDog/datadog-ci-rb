# frozen_string_literal: true

require "set"

require_relative "../ext/app_types"
require_relative "../ext/test"
require_relative "../utils/test_run"

module Datadog
  module CI
    module TestVisibility
      # special kind of traces transport that collects skippable_test_id for all tests in memory
      # as well as counts an overall number of tests and how many were skipped by ITR (aka Test Optimiser)
      class StatsCollector
        def initialize
          @tests = Set.new
          @skipped_count = 0
          @total_count = 0
        end

        def send_traces(traces)
          Datadog.logger.debug("Collecting stats for #{traces.count} traces...")

          traces.each do |trace|
            trace.spans.each do |span|
              next unless span.type == Ext::AppTypes::TYPE_TEST

              @total_count += 1
              if span.get_tag(Ext::Test::TAG_ITR_SKIPPED_BY_ITR) == "true"
                @skipped_count += 1
              end

              @tests << Utils::TestRun.skippable_test_id(
                span.get_tag(Ext::Test::TAG_NAME),
                span.get_tag(Ext::Test::TAG_SUITE),
                span.get_tag(Ext::Test::TAG_PARAMETERS)
              )
            end
          end

          Datadog.logger.debug("Current stats: #{@skipped_count} skipped out of #{@total_count} total tests")

          []
        end
      end
    end
  end
end
