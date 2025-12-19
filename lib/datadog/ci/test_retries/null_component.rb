# frozen_string_literal: true

require_relative "component"

module Datadog
  module CI
    module TestRetries
      class NullComponent < Component
        def initialize
        end

        def configure(library_settings)
        end

        def with_retries(&block)
          yield
        end

        def reset_retries!
        end

        def should_retry?
          false
        end
      end
    end
  end
end
