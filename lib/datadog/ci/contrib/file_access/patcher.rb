# frozen_string_literal: true

require "pathname"

require_relative "../patcher"
require_relative "instrumentation"

module Datadog
  module CI
    module Contrib
      module FileAccess
        module Patcher
          include Contrib::Patcher

          module_function

          def patch
            ::File.prepend(Instrumentation::InstanceMethods)
            ::File.singleton_class.prepend(Instrumentation::ClassMethods)
            ::Pathname.prepend(Instrumentation::PathnameMethods)
          end
        end
      end
    end
  end
end
