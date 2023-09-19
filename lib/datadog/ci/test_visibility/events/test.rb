# frozen_string_literal: true

require_relative "event"

module Datadog
  module CI
    module TestVisibility
      module Events
        class Test < Event
          def initialize
          end
        end
      end
    end
  end
end
