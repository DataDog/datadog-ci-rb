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

              coverage = ::SimpleCov::UselessResultsRemover.call(
                ::SimpleCov::ResultAdapter.call(::Coverage.peek_result)
              )

              __dd_build_result(coverage)
            end

            def datadog_configuration
              Datadog.configuration.ci[:simplecov]
            end

            private

            def __dd_build_result(coverage)
              processed = if respond_to?(:inject_unloaded_files)
                inject_unloaded_files(coverage, __dd_tracked_paths)
              elsif respond_to?(:add_not_loaded_files, true)
                send(:add_not_loaded_files, coverage)
              else
                coverage
              end

              # SimpleCov 1.0 changed unloaded file injection to return a
              # [coverage, not_loaded_files] tuple instead of a coverage hash.
              if processed.is_a?(::Array)
                coverage, not_loaded_files = processed
                result_parameters = ::SimpleCov::Result.instance_method(:initialize).parameters

                if result_parameters.include?([:key, :not_loaded_files])
                  ::SimpleCov::Result.new(coverage, not_loaded_files: not_loaded_files)
                else
                  ::SimpleCov::Result.new(coverage)
                end
              else
                ::SimpleCov::Result.new(processed)
              end
            end

            def __dd_tracked_paths
              globs = [tracked_files, *cover_globs].compact
              return [] if globs.empty?

              ::SimpleCov::UnloadedFileInjector.discover(globs, root: root)
            end
          end
        end
      end
    end
  end
end
