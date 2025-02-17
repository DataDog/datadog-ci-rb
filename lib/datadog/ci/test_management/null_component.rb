# frozen_string_literal: true

require_relative "../ext/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module TestManagement
      class NullComponent
        attr_reader :enabled, :tests_properties

        def initialize
          @enabled = false
          @tests_properties = {}
        end

        def configure(_, _)
        end
      end
    end
  end
end
