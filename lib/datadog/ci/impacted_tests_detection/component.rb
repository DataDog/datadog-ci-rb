# frozen_string_literal: true

require "set"

module Datadog
  module CI
    module ImpactedTestsDetection
      class Component
        def initialize(enabled:)
          @enabled = enabled
          @changed_files = Set.new
        end

        def configure(library_settings, test_session)
          @enabled &&= library_settings.impacted_tests_enabled?
          return unless @enabled

          base_commit_sha = test_session.base_commit_sha
          if base_commit_sha.nil?
            Datadog.logger.warn { "Impacted tests detection disabled: base commit not found" }
            @enabled = false
            return
          end

          changed_files = Datadog::CI::Git::LocalRepository.get_changed_files_from_diff(base_commit_sha)
          if changed_files.nil?
            Datadog.logger.warn { "Impacted tests detection disabled: could not get changed files" }
            @enabled = false
            return
          end

          @changed_files = changed_files
          @enabled = true
        end

        def enabled?
          @enabled
        end
      end
    end
  end
end
