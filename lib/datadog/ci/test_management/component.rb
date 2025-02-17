# frozen_string_literal: true

module Datadog
  module CI
    module TestManagement
      # Test management is a feature that lets people manage their flaky tests in Datadog.
      # It includes:
      # - marking test as quarantined causes test to continue running but not failing the build
      # - marking test as disabled causes test to be skipped
      # - marking test as "attempted to fix" causes test to be retried many times to confirm that fix worked
      class Component
        def initialize(
          enabled:,
          attempt_to_fix_retries_count:
        )
          @enabled = enabled
          @attempt_to_fix_retries_count = attempt_to_fix_retries_count
        end

        def configure(library_settings, test_session)
          @enabled ||= library_settings.test_management_enabled?

          nil unless @enabled

          # fetch test management tests properties from the backend here
        end
      end
    end
  end
end
