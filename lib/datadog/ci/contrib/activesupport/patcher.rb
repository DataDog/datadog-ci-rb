# frozen_string_literal: true

require_relative "../patcher"
require_relative "formatter"

module Datadog
  module CI
    module Contrib
      module ActiveSupport
        # Patcher enables patching of activesupport module
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            return unless ::Rails.logger.formatter.is_a?(::ActiveSupport::TaggedLogging::Formatter)

            ::ActiveSupport::TaggedLogging::Formatter.include(Formatter)
          end
        end
      end
    end
  end
end
