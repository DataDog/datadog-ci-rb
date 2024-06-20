# frozen_string_literal: true

require "set"

require_relative "../ext/app_types"
require_relative "../ext/test"
require_relative "../utils/test_run"

module Datadog
  module CI
    module TestVisibility
      class StatsCollector
        def initialize
        end

        def send_traces(traces)
          []
        end
      end
    end
  end
end
