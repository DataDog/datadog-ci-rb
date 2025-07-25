# frozen_string_literal: true

require_relative "../patcher"

require_relative "example"
require_relative "example_group"
require_relative "runner"
require_relative "documentation_formatter"

module Datadog
  module CI
    module Contrib
      module RSpec
        # Patcher enables patching of 'rspec' module.
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            ::RSpec::Core::Runner.include(Runner)
            ::RSpec::Core::Example.include(Example)
            ::RSpec::Core::ExampleGroup.include(ExampleGroup)

            # only add DocumentationFormatter's patch if it's loaded at this point
            if defined?(::RSpec::Core::Formatters::DocumentationFormatter) &&
                defined?(::RSpec::Core::Formatters::BaseFormatter) &&
                defined?(::RSpec::Core::Formatters::BaseTextFormatter)
              ::RSpec::Core::Formatters::DocumentationFormatter.include(DocumentationFormatter)
            end
          end
        end
      end
    end
  end
end
