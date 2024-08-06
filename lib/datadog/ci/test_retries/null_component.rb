# frozen_string_literal: true

require_relative "component"

module Datadog
  module CI
    module TestRetries
      class NullComponent < Component
        attr_reader :retry_failed_tests_enabled, :retry_failed_tests_max_attempts, :retry_failed_tests_total_limit

        def initialize
          # enabled only by remote settings
          @retry_failed_tests_enabled = false
          @retry_failed_tests_max_attempts = 0
          @retry_failed_tests_total_limit = 0
        end

        def configure(library_settings)
        end

        def with_retries(&block)
          no_action = proc {}
          yield no_action
        end
      end
    end
  end
end
