# frozen_string_literal: true

require "coverage"

module Datadog
  module CI
    module Contrib
      module Simplecov
        module ResultExtractor
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          module ClassMethods
            def __dd_peek_result
              unless datadog_configuration[:enabled]
                Datadog.logger.debug("SimpleCov instrumentation is disabled")
                return nil
              end

              result = ::SimpleCov::UselessResultsRemover.call(
                ::SimpleCov::ResultAdapter.call(::Coverage.peek_result)
              )

              if respond_to?(:add_not_loaded_files, true)
                # SimpleCov 1.0 changed add_not_loaded_files to return a
                # [coverage, not_loaded_files] tuple instead of a coverage hash.
                processed = add_not_loaded_files(result)
                if processed.is_a?(::Array)
                  coverage, not_loaded_files = processed
                  ::SimpleCov::Result.new(coverage, not_loaded_files: not_loaded_files)
                else
                  ::SimpleCov::Result.new(processed)
                end
              else
                # SimpleCov 1.1 replaced add_not_loaded_files with these result
                # processing APIs and records the tracked paths on the result.
                tracked_files = tracked_file_paths - result.keys
                coverage, not_loaded_files = inject_unloaded_files(result, tracked_files)
                ::SimpleCov::Result.new(
                  coverage,
                  not_loaded_files: not_loaded_files,
                  tracked_files: tracked_files
                )
              end
            end

            def datadog_configuration
              Datadog.configuration.ci[:simplecov]
            end
          end
        end
      end
    end
  end
end
