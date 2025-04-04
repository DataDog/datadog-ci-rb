# frozen_string_literal: true

module Datadog
  module CI
    module Logs
      class Component
        attr_reader :enabled

        def initialize(enabled:)
          @enabled = enabled
        end

        def write(event)
          return unless enabled

          # p event

          event
        end
      end
    end
  end
end
