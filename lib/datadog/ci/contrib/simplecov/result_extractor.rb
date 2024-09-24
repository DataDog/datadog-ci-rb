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
              return nil unless datadog_configuration[:enabled]

              result = ::SimpleCov::UselessResultsRemover.call(
                ::SimpleCov::ResultAdapter.call(::Coverage.peek_result)
              )

              ::SimpleCov::Result.new(add_not_loaded_files(result))
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
