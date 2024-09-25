# frozen_string_literal: true

require "datadog/tracing/contrib/patcher"

require_relative "result_extractor"

module Datadog
  module CI
    module Contrib
      module Simplecov
        # Patcher enables patching of 'SimpleCov' module.
        module Patcher
          include Datadog::Tracing::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::SimpleCov.include(ResultExtractor)
          end
        end
      end
    end
  end
end
