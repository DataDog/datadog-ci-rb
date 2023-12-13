# frozen_string_literal: true

require "datadog/tracing/contrib/patcher"

require_relative "example"
require_relative "example_group"
require_relative "runner"

module Datadog
  module CI
    module Contrib
      module RSpec
        # Patcher enables patching of 'rspec' module.
        module Patcher
          include Datadog::Tracing::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::RSpec::Core::Example.include(Example)
            ::RSpec::Core::Runner.include(Runner)
            ::RSpec::Core::ExampleGroup.include(ExampleGroup)
          end
        end
      end
    end
  end
end
