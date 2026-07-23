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

              # SimpleCov 1.0 changed add_not_loaded_files to return a
              # [coverage, not_loaded_files] tuple instead of a coverage hash.
              processed = add_not_loaded_files(result)
              if processed.is_a?(::Array)
                coverage, not_loaded_files = processed
                ::SimpleCov::Result.new(coverage, not_loaded_files: not_loaded_files)
              else
                ::SimpleCov::Result.new(processed)
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
