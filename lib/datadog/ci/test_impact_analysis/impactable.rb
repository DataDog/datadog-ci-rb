# frozen_string_literal: true

module Datadog
  module CI
    module TestImpactAnalysis
      # Stores files that Test Impact Analysis should consider capable of
      # impacting a test or every test in a suite.
      #
      # @internal
      module Impactable
        MAX_IMPACTED_FILES = 10_000

        # Adds files that Test Impact Analysis should consider capable of
        # impacting this test, or every test in this suite.
        #
        # When any of these files changes, Test Impact Analysis will not skip
        # the affected test or suite. This is useful for files that cannot be
        # observed by Datadog's Ruby coverage instrumentation, such as
        # JavaScript executed in a browser during a Capybara test.
        #
        # Paths may be absolute or relative to the current working directory.
        # They are normalized to paths relative to the repository root when the
        # coverage event is serialized.
        #
        # @example Register JavaScript files loaded during an RSpec test
        #   RSpec.configure do |config|
        #     config.after do
        #       Datadog::CI.active_test&.add_impacted_files(
        #         javascript_files_loaded_by_browser
        #       )
        #     end
        #   end
        #
        # @example Register JavaScript setup shared by an RSpec suite
        #   before(:context) do
        #     Datadog::CI.active_test_suite&.add_impacted_files(
        #       ["app/frontend/test_setup.js"]
        #     )
        #   end
        #
        # A test or test suite can have at most 10,000 unique impacted files.
        # Additional files are ignored and a warning is logged.
        #
        # Test suite impacted files must be added before any test in the suite
        # finishes.
        #
        # @param [Array<String>] file_paths paths that can impact the test or suite
        # @return [void]
        def add_impacted_files(file_paths)
          raise ArgumentError, "file_paths must be an Array" unless file_paths.is_a?(Array)

          add_impacted_files_unchecked(file_paths)
        end

        # Returns files explicitly marked as impacting this test or suite for
        # Test Impact Analysis.
        #
        # The returned array is frozen. Use {#add_impacted_files} or
        # {#clear_impacted_files} to update the tracked files. A previously
        # returned array is not changed by later updates.
        #
        # @return [Array<String>] paths that can impact the test or suite
        def impacted_files
          custom_impacted_files.freeze
        end

        # Clears files explicitly marked as impacting this test or suite for
        # Test Impact Analysis.
        #
        # @return [void]
        def clear_impacted_files
          impacted_files = custom_impacted_files
          if impacted_files.frozen?
            @custom_impacted_files = []
          else
            impacted_files.clear
          end
          @custom_impacted_files_index = nil

          nil
        end

        private

        def add_impacted_files_unchecked(file_paths)
          if @custom_impacted_files.nil?
            new_files = file_paths.uniq
            if new_files.size > MAX_IMPACTED_FILES
              new_files = new_files.first(MAX_IMPACTED_FILES)
              warn_impacted_files_limit
            end

            @custom_impacted_files = new_files
          else
            impacted_files = mutable_custom_impacted_files
            impacted_files_index = custom_impacted_files_index
            file_paths.each do |file_path|
              next if impacted_files_index.key?(file_path)

              if impacted_files.size >= MAX_IMPACTED_FILES
                warn_impacted_files_limit
                break
              end

              impacted_files << file_path
              impacted_files_index[file_path] = true
            end
          end

          nil
        end

        def custom_impacted_files
          @custom_impacted_files ||= []
        end

        def mutable_custom_impacted_files
          impacted_files = custom_impacted_files
          if impacted_files.frozen?
            impacted_files = impacted_files.dup
            @custom_impacted_files = impacted_files
          end
          impacted_files
        end

        def custom_impacted_files_index
          @custom_impacted_files_index ||= custom_impacted_files.each_with_object({}) do |file_path, index|
            index[file_path] = true
          end
        end

        def impacted_files_limit_scope
          "test"
        end

        def warn_impacted_files_limit
          Datadog.logger.warn(
            "Test Impact Analysis supports at most #{MAX_IMPACTED_FILES} impacted files per " \
            "#{impacted_files_limit_scope}; additional files will be ignored"
          )
        end
      end
    end
  end
end
