# frozen_string_literal: true

module Datadog
  module CI
    module CodeCoverage
      class NullComponent
        attr_reader :enabled

        def initialize
          @enabled = false
        end

        def configure(library_configuration)
        end

        def upload(serialized_report:, format:)
        end

        def shutdown!
        end
      end
    end
  end
end
