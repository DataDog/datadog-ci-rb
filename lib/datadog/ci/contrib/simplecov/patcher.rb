# frozen_string_literal: true

require_relative "../patcher"

require_relative "report_uploader"
require_relative "result_extractor"

module Datadog
  module CI
    module Contrib
      module Simplecov
        # Patcher enables patching of 'SimpleCov' module.
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            ::SimpleCov.include(ResultExtractor)
            ::SimpleCov.include(ReportUploader)
          end
        end
      end
    end
  end
end
