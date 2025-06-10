# frozen_string_literal: true

require "set"

require_relative "../ext/test"
require_relative "../git/local_repository"

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

          # we must unshallow the repository before trying to find base_commit_sha or executing `git diff` command
          git_tree_upload_worker.wait_until_done

          base_commit_sha = test_session.base_commit_sha || Git::LocalRepository.base_commit_sha
          if base_commit_sha.nil?
            Datadog.logger.debug { "Impacted tests detection disabled: base commit not found" }
            @enabled = false
            return
          end

          changed_files = Git::LocalRepository.get_changes_since(base_commit_sha)
          if changed_files.nil?
            Datadog.logger.debug { "Impacted tests detection disabled: could not get changed files" }
            @enabled = false
            return
          end

          Datadog.logger.debug do
            "Impacted tests detection: found #{changed_files.size} changed files"
          end
          Datadog.logger.debug do
            "Impacted tests detection: changed files: #{changed_files.inspect}"
          end

          @changed_files = changed_files
          @enabled = true
        end

        def enabled?
          @enabled
        end

        def modified?(test_span)
          return false unless enabled?

          source_file = test_span.source_file
          return false if source_file.nil?

          @changed_files.include?(source_file)
        end

        def tag_modified_test(test_span)
          return unless modified?(test_span)

          Datadog.logger.debug do
            "Impacted tests detection: test #{test_span.name} with source file #{test_span.source_file} is modified"
          end

          test_span.set_tag(Ext::Test::TAG_TEST_IS_MODIFIED, "true")
        end

        private

        def git_tree_upload_worker
          Datadog.send(:components).git_tree_upload_worker
        end
      end
    end
  end
end
