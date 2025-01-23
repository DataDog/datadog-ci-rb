# frozen_string_literal: true

require_relative "../patcher"

require_relative "driver"

module Datadog
  module CI
    module Contrib
      module Cuprite
        # Patcher enables patching of 'Capybara::Cuprite::Driver' class.
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            ::Capybara::Cuprite::Driver.include(Driver)
          end
        end
      end
    end
  end
end
